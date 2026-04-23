# PMC DTE – License Protection System
## Complete Setup Guide

---

## 📁 What's in this package

| File | Purpose |
|------|---------|
| `PMC_DTE_Protected.mq5` | The indicator with license check built in |
| `license_server/server.py` | Python web server that validates keys |
| `license_server/requirements.txt` | Python dependencies (just Flask) |
| `license_server/render.yaml` | One-click deploy config for Render.com |

---

## 🚀 STEP 1 — Deploy the License Server (Free)

### Option A: Render.com (recommended, free tier)

1. Create a free account at https://render.com
2. Create a new GitHub repo and push the `license_server/` folder into it
3. In Render → New → Web Service → connect your repo
4. Render detects `render.yaml` automatically
5. Set environment variable `ADMIN_PASSWORD` to a strong password in the Render dashboard
6. Deploy → your server URL will be: `https://pmc-license-server.onrender.com`

### Option B: Railway.app (also free tier)

1. Create account at https://railway.app
2. New project → Deploy from GitHub repo
3. Set env vars: `ADMIN_PASSWORD`, `SECRET_SALT` (any random string)
4. Done — Railway gives you a URL like `https://pmc-license-server.up.railway.app`

---

## 🔧 STEP 2 — Update the Indicator

Open `PMC_DTE_Protected.mq5` and change line:

```cpp
#define LICENSE_SERVER   "https://your-license-server.com"
```

→ Replace with your actual Render/Railway URL, e.g.:

```cpp
#define LICENSE_SERVER   "https://pmc-license-server.onrender.com"
```

Then **compile** in MetaEditor (F7) → distribute only the compiled `.ex5` file.
**Never share the .mq5 source.**

---

## ⚙️ STEP 3 — Configure MT5 (one-time per student)

Students must whitelist your server URL in MetaTrader 5:

1. `Tools` → `Options` → `Expert Advisors` tab
2. Check ✅ **"Allow WebRequest for listed URL"**
3. Add your server URL: `https://pmc-license-server.onrender.com`
4. Click OK

---

## 👨‍💼 STEP 4 — Managing Students (Admin Panel)

Go to: `https://your-server-url.com/admin`
Login with your `ADMIN_PASSWORD`.

### Issue a new key
- Enter student name/email, set duration in months → click **Generate Key**
- Copy the key (format: `PMCD-XXXX-XXXX-XXXX`) and send it to the student

### Student activates their copy
- Open MT5 → attach indicator to chart
- In the Inputs tab, paste the key into **"Your License Key"**
- The indicator auto-binds to their MT5 account number on first use

### Renew a subscription
- Find the student row → enter `1` (or more months) → click **+Renew**
- The expiry date extends automatically

### Revoke access (non-payment)
- Click **Revoke** → indicator immediately shows error on their chart at next hourly check

### Student changed PC / MT5 account
- Click **Reset Acct** → removes the account lock → student can re-bind with same key

---

## 🔒 Security Notes

- **Only distribute the compiled `.ex5`** — never the `.mq5` source
- The key is bound to one MT5 account number on first use
- Re-validation happens every hour while MT5 is open
- A 24-hour grace period applies if your server is temporarily unreachable
  (protects students from false lockouts, while still enforcing payment within 24h)
- Use HTTPS on your server (Render/Railway provide this automatically)

---

## 💰 Suggested Student Workflow

1. Student pays via your preferred method (Stripe, PayPal, bank transfer)
2. You issue a key in the admin panel for N months
3. You send the key + the `.ex5` file + MT5 setup instructions to the student
4. Month ends → key auto-expires → student pays again → you click Renew

---

## 📞 Support

If a student's indicator shows:
| Error | Cause | Fix |
|-------|-------|-----|
| `Invalid License Key ❌` | Wrong key entered | Re-send correct key |
| `License Expired ❌` | Subscription ended | Click Renew in admin |
| `Account Mismatch ❌` | Different MT5 account | Click Reset Acct |
| `Enable WebRequest ⚠️` | MT5 not configured | Guide student through Step 3 |
| `Cannot reach license server ❌` | Server down / network | Check Render dashboard |
