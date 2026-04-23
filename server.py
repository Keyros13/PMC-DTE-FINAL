"""
PMC DTE – License Server
========================
Stack : Python 3.10+  |  Flask  |  SQLite (zero-config, file-based)
Deploy: Render.com / Railway.app / any VPS – FREE tier works fine

Quick start (local test):
    pip install flask
    python server.py

Environment variables (set on your hosting platform):
    ADMIN_PASSWORD   – password for the /admin panel  (default: changeme)
    SECRET_SALT      – random string used for key hashing (keep private!)
    PORT             – port to listen on               (default: 5000)
"""

import os
import sqlite3
import secrets
import hashlib
import string
from datetime import datetime, timedelta
from functools import wraps

from flask import Flask, request, jsonify, g, render_template_string, redirect, \
                  url_for, session, abort

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_SALT", "change-this-secret-salt-in-production")

ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD", "changeme")
DB_PATH        = os.environ.get("DB_PATH", "licenses.db")
PRODUCT_ID     = "PMC_DTE_v1"

# ---------------------------------------------------------------------------
# DATABASE
# ---------------------------------------------------------------------------

def get_db():
    if "db" not in g:
        g.db = sqlite3.connect(DB_PATH, detect_types=sqlite3.PARSE_DECLTYPES)
        g.db.row_factory = sqlite3.Row
    return g.db

@app.teardown_appcontext
def close_db(e=None):
    db = g.pop("db", None)
    if db:
        db.close()

def init_db():
    db = sqlite3.connect(DB_PATH)
    db.execute("""
        CREATE TABLE IF NOT EXISTS licenses (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            key         TEXT    NOT NULL UNIQUE,
            product     TEXT    NOT NULL DEFAULT 'PMC_DTE_v1',
            student     TEXT    NOT NULL,          -- student name / email
            account     TEXT    DEFAULT NULL,      -- MT5 account number (locked after first use)
            status      TEXT    NOT NULL DEFAULT 'active',  -- active | expired | revoked
            expires_at  TEXT    NOT NULL,          -- ISO date string  YYYY-MM-DD
            created_at  TEXT    NOT NULL DEFAULT (datetime('now')),
            last_seen   TEXT    DEFAULT NULL,
            notes       TEXT    DEFAULT ''
        )
    """)
    db.commit()
    db.close()
    print("[DB] Initialized →", DB_PATH)

# ---------------------------------------------------------------------------
# KEY GENERATOR
# ---------------------------------------------------------------------------

def generate_key():
    """Returns a key like  PMCD-A1B2-C3D4-E5F6"""
    chars  = string.ascii_uppercase + string.digits
    groups = ["".join(secrets.choice(chars) for _ in range(4)) for _ in range(4)]
    return "PMCD-" + "-".join(groups[1:])   # prefix PMCD for brand recognition

# ---------------------------------------------------------------------------
# VALIDATE ENDPOINT  (called by the MT5 indicator)
# GET /validate?key=KEY&account=ACCOUNT&product=PRODUCT
# Returns plain text: OK | EXPIRED | INVALID | ACCOUNT_MISMATCH | REVOKED
# ---------------------------------------------------------------------------

@app.route("/validate")
def validate():
    key     = request.args.get("key",     "").strip().upper()
    account = request.args.get("account", "").strip()
    product = request.args.get("product", "").strip()

    if not key or not account:
        return "INVALID", 200

    db  = get_db()
    row = db.execute(
        "SELECT * FROM licenses WHERE key = ? AND product = ?",
        (key, product or PRODUCT_ID)
    ).fetchone()

    if not row:
        return "INVALID", 200

    if row["status"] == "revoked":
        return "REVOKED", 200

    # Check expiry
    try:
        expires = datetime.fromisoformat(row["expires_at"])
    except ValueError:
        return "INVALID", 200

    if datetime.utcnow() > expires:
        db.execute("UPDATE licenses SET status='expired' WHERE key=?", (key,))
        db.commit()
        return "EXPIRED", 200

    # Account lock: bind key to first MT5 account that uses it
    if row["account"] is None:
        db.execute("UPDATE licenses SET account=? WHERE key=?", (account, key))
        db.commit()
    elif row["account"] != account:
        return "ACCOUNT_MISMATCH", 200

    # All good – update last_seen
    db.execute("UPDATE licenses SET last_seen=datetime('now') WHERE key=?", (key,))
    db.commit()

    return "OK", 200

# ---------------------------------------------------------------------------
# ADMIN AUTH
# ---------------------------------------------------------------------------

def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get("admin"):
            return redirect(url_for("admin_login"))
        return f(*args, **kwargs)
    return decorated

@app.route("/admin/login", methods=["GET", "POST"])
def admin_login():
    error = ""
    if request.method == "POST":
        if request.form.get("password") == ADMIN_PASSWORD:
            session["admin"] = True
            return redirect(url_for("admin_panel"))
        error = "Wrong password."
    return render_template_string(LOGIN_HTML, error=error)

@app.route("/admin/logout")
def admin_logout():
    session.clear()
    return redirect(url_for("admin_login"))

# ---------------------------------------------------------------------------
# ADMIN PANEL
# ---------------------------------------------------------------------------

@app.route("/admin")
@login_required
def admin_panel():
    db   = get_db()
    rows = db.execute("SELECT * FROM licenses ORDER BY created_at DESC").fetchall()
    return render_template_string(ADMIN_HTML, licenses=rows)

@app.route("/admin/create", methods=["POST"])
@login_required
def admin_create():
    student  = request.form.get("student", "").strip()
    months   = int(request.form.get("months", 1))
    notes    = request.form.get("notes", "").strip()

    if not student:
        abort(400, "Student name required")

    key        = generate_key()
    expires_at = (datetime.utcnow() + timedelta(days=30 * months)).strftime("%Y-%m-%d")

    db = get_db()
    db.execute(
        "INSERT INTO licenses (key, product, student, expires_at, notes) VALUES (?,?,?,?,?)",
        (key, PRODUCT_ID, student, expires_at, notes)
    )
    db.commit()
    return redirect(url_for("admin_panel"))

@app.route("/admin/revoke/<int:lid>", methods=["POST"])
@login_required
def admin_revoke(lid):
    db = get_db()
    db.execute("UPDATE licenses SET status='revoked' WHERE id=?", (lid,))
    db.commit()
    return redirect(url_for("admin_panel"))

@app.route("/admin/renew/<int:lid>", methods=["POST"])
@login_required
def admin_renew(lid):
    months = int(request.form.get("months", 1))
    db     = get_db()
    row    = db.execute("SELECT expires_at, status FROM licenses WHERE id=?", (lid,)).fetchone()
    if not row:
        abort(404)

    # Renew from today if expired, otherwise extend from current expiry
    base = datetime.utcnow()
    if row["status"] == "active":
        try:
            base = max(base, datetime.fromisoformat(row["expires_at"]))
        except Exception:
            pass

    new_expiry = (base + timedelta(days=30 * months)).strftime("%Y-%m-%d")
    db.execute(
        "UPDATE licenses SET expires_at=?, status='active' WHERE id=?",
        (new_expiry, lid)
    )
    db.commit()
    return redirect(url_for("admin_panel"))

@app.route("/admin/reset_account/<int:lid>", methods=["POST"])
@login_required
def admin_reset_account(lid):
    """Unlock a key from its bound MT5 account (e.g. student changed PC)."""
    db = get_db()
    db.execute("UPDATE licenses SET account=NULL WHERE id=?", (lid,))
    db.commit()
    return redirect(url_for("admin_panel"))

# ---------------------------------------------------------------------------
# HTML TEMPLATES
# ---------------------------------------------------------------------------

LOGIN_HTML = """
<!DOCTYPE html>
<html>
<head>
  <title>PMC License Admin</title>
  <style>
    body { font-family: monospace; background: #0d0d0d; color: #e0e0e0;
           display:flex; align-items:center; justify-content:center; height:100vh; margin:0; }
    .box { background:#1a1a1a; padding:2rem; border:1px solid #333; border-radius:8px; width:320px; }
    h2   { color:#ffd700; margin-top:0; }
    input[type=password] { width:100%; padding:.5rem; background:#111; border:1px solid #444;
                           color:#fff; border-radius:4px; margin:.5rem 0 1rem; box-sizing:border-box; }
    button { background:#ffd700; color:#000; border:none; padding:.6rem 1.4rem;
             border-radius:4px; cursor:pointer; font-weight:bold; }
    .err   { color:#ff4444; font-size:.85rem; }
  </style>
</head>
<body>
  <div class="box">
    <h2>🔐 PMC License Admin</h2>
    {% if error %}<p class="err">{{ error }}</p>{% endif %}
    <form method="POST">
      <input type="password" name="password" placeholder="Admin password" autofocus>
      <button type="submit">Login</button>
    </form>
  </div>
</body>
</html>
"""

ADMIN_HTML = """
<!DOCTYPE html>
<html>
<head>
  <title>PMC License Admin</title>
  <style>
    * { box-sizing:border-box; }
    body { font-family: monospace; background:#0d0d0d; color:#e0e0e0; margin:0; padding:1rem; }
    h1   { color:#ffd700; }
    a    { color:#ffd700; }
    table { width:100%; border-collapse:collapse; font-size:.82rem; margin-top:1rem; }
    th   { background:#1a1a1a; color:#ffd700; padding:.5rem; text-align:left; border-bottom:1px solid #333; }
    td   { padding:.45rem .5rem; border-bottom:1px solid #222; vertical-align:top; }
    tr:hover td { background:#151515; }
    .active  { color:#4cff72; }
    .expired { color:#ff4444; }
    .revoked { color:#888; }
    .card    { background:#1a1a1a; padding:1rem 1.4rem; border:1px solid #333;
               border-radius:8px; display:inline-block; margin-bottom:1.5rem; }
    input[type=text], input[type=number], select {
      background:#111; border:1px solid #444; color:#fff;
      padding:.35rem .5rem; border-radius:4px; }
    button, .btn {
      background:#ffd700; color:#000; border:none; padding:.35rem .8rem;
      border-radius:4px; cursor:pointer; font-weight:bold; font-size:.8rem; }
    .btn-danger  { background:#c0392b; color:#fff; }
    .btn-neutral { background:#444;    color:#fff; }
    .key  { letter-spacing:.05em; color:#aef; }
    .logout { float:right; margin-top:.3rem; }
  </style>
</head>
<body>
  <h1>📋 PMC License Dashboard <a class="logout btn btn-neutral" href="/admin/logout">Logout</a></h1>

  <!-- CREATE KEY FORM -->
  <div class="card">
    <b style="color:#ffd700">➕ Issue New License</b><br><br>
    <form method="POST" action="/admin/create">
      Student name / email:&nbsp;
      <input type="text" name="student" placeholder="e.g. Jean Dupont" size="22" required>
      &nbsp; Months:&nbsp;
      <input type="number" name="months" value="1" min="1" max="24" style="width:55px">
      &nbsp; Notes:&nbsp;
      <input type="text" name="notes" placeholder="optional" size="18">
      &nbsp;<button type="submit">Generate Key</button>
    </form>
  </div>

  <!-- LICENSES TABLE -->
  <table>
    <tr>
      <th>#</th><th>Student</th><th>Key</th><th>Status</th>
      <th>Expires</th><th>MT5 Account</th><th>Last Seen</th><th>Actions</th>
    </tr>
    {% for lic in licenses %}
    <tr>
      <td>{{ lic.id }}</td>
      <td>{{ lic.student }}<br><small style="color:#666">{{ lic.notes }}</small></td>
      <td class="key">{{ lic.key }}</td>
      <td class="{{ lic.status }}">{{ lic.status.upper() }}</td>
      <td>{{ lic.expires_at }}</td>
      <td>{{ lic.account or '—' }}</td>
      <td>{{ lic.last_seen or 'never' }}</td>
      <td>
        <!-- Renew -->
        <form method="POST" action="/admin/renew/{{ lic.id }}" style="display:inline">
          <input type="number" name="months" value="1" min="1" max="24" style="width:45px">
          <button type="submit">+Renew</button>
        </form>
        &nbsp;
        <!-- Revoke -->
        <form method="POST" action="/admin/revoke/{{ lic.id }}" style="display:inline"
              onsubmit="return confirm('Revoke key for {{ lic.student }}?')">
          <button type="submit" class="btn btn-danger">Revoke</button>
        </form>
        &nbsp;
        <!-- Reset account lock -->
        <form method="POST" action="/admin/reset_account/{{ lic.id }}" style="display:inline"
              onsubmit="return confirm('Reset MT5 account lock?')">
          <button type="submit" class="btn btn-neutral">Reset Acct</button>
        </form>
      </td>
    </tr>
    {% endfor %}
  </table>
</body>
</html>
"""

# ---------------------------------------------------------------------------
# ENTRY POINT
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    init_db()
    port = int(os.environ.get("PORT", 5000))
    print(f"[PMC License Server] Running on http://0.0.0.0:{port}")
    print(f"[PMC License Server] Admin panel → http://localhost:{port}/admin")
    app.run(host="0.0.0.0", port=port, debug=False)
