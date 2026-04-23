//+------------------------------------------------------------------+
//|                      PMC_DTE_Protected.mq5                       |
//|              Protocole MC – Day Trading Entry (DTE)              |
//|          License-protected  |  GMT+3  |  MQL5                    |
//+------------------------------------------------------------------+
#property copyright   "Protocole MC – DTE"
#property version     "1.10"
#property description "Momentum Candlesticks – Day Trading Entry System (Licensed)"
#property indicator_chart_window
#property indicator_plots 0

//=============================================================================
// LICENSE SERVER CONFIGURATION
// IMPORTANT: Replace LICENSE_SERVER with your actual deployed server URL
//=============================================================================
#define LICENSE_SERVER   "https://your-license-server.com"
#define PRODUCT_ID       "PMC_DTE_v1"
#define CHECK_INTERVAL   3600   // re-validate every hour (seconds)

//=============================================================================
// INPUT PARAMETERS
//=============================================================================

// --- License ---
input group "=== License ==="
input string InpLicenseKey = "XXXX-XXXX-XXXX-XXXX"; // Your License Key

// --- Marubozu Sensitivity ---
input group "=== Marubozu Settings ==="
input double InpMarubozuWickRatio = 2.0;   // Max wick/body ratio (default 2.0)

// --- EQ Lines ---
input group "=== EQ Lines ==="
input bool   InpShowEQ1          = true;   // Show EQ1 (Yesterday Open)
input bool   InpShowEQ2          = true;   // Show EQ2 (Today Open)
input color  InpEQColor          = clrCrimson; // EQ Lines Color
input int    InpEQLineWidth       = 2;      // EQ Line Width
input ENUM_LINE_STYLE InpEQStyle = STYLE_SOLID; // EQ Line Style

// --- FEZ Rectangle ---
input group "=== Focus Entry Zone (FEZ) ==="
input bool   InpShowFEZ          = true;   // Show FEZ Rectangle
input color  InpFEZColor         = clrGold;// FEZ Border Color
input int    InpFEZLineWidth      = 2;      // FEZ Border Width

// --- Labels ---
input group "=== Dashboard Labels ==="
input int    InpLabelFontSize    = 10;     // Label Font Size
input string InpLabelFont        = "Consolas"; // Label Font

// --- Edge Scoring (manual inputs – trader sets these per session) ---
input group "=== DTE Edge Scoring (8/10 Min) ==="
input bool   InpEdge_Alignment       = false; // Alignment met? (2 pts)
input bool   InpEdge_StrongMedium    = false; // Strong Momentum? (2 pts)
input bool   InpEdge_IntermMedium    = false; // Intermediate Momentum? (1 pt)
input bool   InpEdge_BaseNumber      = false; // Base Number < 5? (2 pts)
input bool   InpEdge_RR              = false; // RR 1:3 Min met? (2 pts)
input bool   InpEdge_FreshZone       = false; // Fresh Zone? (2 pts)

//=============================================================================
// GLOBAL VARIABLES
//=============================================================================

// Object name prefixes for easy cleanup
#define PREFIX_EQ   "PMC_EQ_"
#define PREFIX_FEZ  "PMC_FEZ_"
#define PREFIX_LBL  "PMC_LBL_"

// Chart constants
const int LABEL_X = 20;   // X offset from right edge (pixels)
int       g_LabelY = 20;  // Y base for top-right labels (pixels)

//=============================================================================
// LICENSE STATE  (do not modify)
//=============================================================================
bool   g_LicenseValid    = false;  // true only after server confirms active key
string g_LicenseMsg      = "";     // message shown to user
datetime g_LastCheck     = 0;      // timestamp of last validation

//+------------------------------------------------------------------+
//| Custom indicator initialization                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Validate inputs
   if(InpMarubozuWickRatio <= 0)
     {
      Alert("PMC DTE: Marubozu wick ratio must be > 0");
      return INIT_PARAMETERS_INCORRECT;
     }

   // ── License check on load ──────────────────────────────────────
   // Allow WebRequest to our license server (must also be added in
   // MT5: Tools → Options → Expert Advisors → Allow WebRequest for:)
   ValidateLicense();

   if(!g_LicenseValid)
     {
      DrawLicenseError();
      // Still start timer so we can retry periodically
      EventSetTimer(CHECK_INTERVAL);
      return INIT_SUCCEEDED; // load indicator but show error, don't crash
     }

   // Force a first draw
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   EventSetTimer(60); // refresh every minute (handles day change)

   // Initial draw
   DrawAll();

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   DeleteAllObjects();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Timer event                                                       |
//+------------------------------------------------------------------+
void OnTimer()
  {
   datetime now = TimeCurrent();

   // Re-validate license every CHECK_INTERVAL seconds
   if(now - g_LastCheck >= CHECK_INTERVAL)
      ValidateLicense();

   if(!g_LicenseValid)
     {
      DeleteAllObjects();
      DrawLicenseError();
      return;
     }

   DrawAll();
  }

//+------------------------------------------------------------------+
//| Called on every new tick – full MQL5 signature required          |
//+------------------------------------------------------------------+
int OnCalculate(const int        rates_total,
                const int        prev_calculated,
                const datetime  &time[],
                const double    &open[],
                const double    &high[],
                const double    &low[],
                const double    &close[],
                const long      &tick_volume[],
                const long      &volume[],
                const int       &spread[])
  {
   // Redraw whenever a new bar appears
   if(prev_calculated != rates_total)
      DrawAll();

   return rates_total;
  }

//=============================================================================
// LICENSE VALIDATION
// Sends GET to: LICENSE_SERVER/validate?key=KEY&account=ACCOUNT&product=PRODUCT
// Server must respond with plain text: "OK" (valid) or "EXPIRED"/"INVALID"/etc.
//=============================================================================
void ValidateLicense()
  {
   g_LastCheck = TimeCurrent();

   // Build the URL
   long   accountNumber = AccountInfoInteger(ACCOUNT_LOGIN);
   string url = LICENSE_SERVER + "/validate"
                + "?key="     + InpLicenseKey
                + "&account=" + IntegerToString(accountNumber)
                + "&product=" + PRODUCT_ID;

   char   postData[];   // empty – GET request
   char   response[];
   string responseHeaders;
   int    timeout = 5000; // 5 seconds

   int httpCode = WebRequest("GET", url, "", "", timeout,
                             postData, 0, response, responseHeaders);

   if(httpCode == 200)
     {
      string body = CharArrayToString(response);
      StringTrimRight(body);
      StringTrimLeft(body);

      if(body == "OK")
        {
         g_LicenseValid = true;
         g_LicenseMsg   = "License Active ✅";
        }
      else if(body == "EXPIRED")
        {
         g_LicenseValid = false;
         g_LicenseMsg   = "License Expired ❌  Please renew.";
        }
      else if(body == "INVALID")
        {
         g_LicenseValid = false;
         g_LicenseMsg   = "Invalid License Key ❌";
        }
      else if(body == "ACCOUNT_MISMATCH")
        {
         g_LicenseValid = false;
         g_LicenseMsg   = "Account Mismatch ❌  Key locked to another account.";
        }
      else
        {
         g_LicenseValid = false;
         g_LicenseMsg   = "License Error ❌  (" + body + ")";
        }
     }
   else if(httpCode == -1)
     {
      // WebRequest not allowed – user must whitelist the URL in MT5 settings
      g_LicenseValid = false;
      g_LicenseMsg   = "⚠️ Enable WebRequest in MT5: Tools→Options→Expert Advisors";
     }
   else
     {
      // Network/server unreachable – grant a 24h grace period so traders
      // aren't locked out by temporary connectivity issues
      if(g_LicenseValid && (TimeCurrent() - g_LastCheck < 86400))
        {
         g_LicenseMsg = "License (offline grace period) ⚠️";
         // keep g_LicenseValid = true during grace period
        }
      else
        {
         g_LicenseValid = false;
         g_LicenseMsg   = "Cannot reach license server ❌  (HTTP " + IntegerToString(httpCode) + ")";
        }
     }
  }

//=============================================================================
// DRAW LICENSE ERROR SCREEN – replaces the indicator display when unlicensed
//=============================================================================
void DrawLicenseError()
  {
   // Background banner
   string bannerName = PREFIX_LBL + "LIC_BANNER";
   ObjectCreate(0, bannerName, OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0,  bannerName, OBJPROP_TEXT,      "◄  PMC DTE – " + g_LicenseMsg + "  ►");
   ObjectSetString(0,  bannerName, OBJPROP_FONT,      "Consolas");
   ObjectSetInteger(0, bannerName, OBJPROP_FONTSIZE,  13);
   ObjectSetInteger(0, bannerName, OBJPROP_COLOR,     clrOrangeRed);
   ObjectSetInteger(0, bannerName, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bannerName, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, bannerName, OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, bannerName, OBJPROP_ANCHOR,    ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, bannerName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bannerName, OBJPROP_HIDDEN,    true);

   // Sub-line with account info
   string subName = PREFIX_LBL + "LIC_SUB";
   ObjectCreate(0, subName, OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0,  subName, OBJPROP_TEXT,
                   "Account #" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))
                   + "  |  Key: " + InpLicenseKey
                   + "  |  Contact your instructor to activate.");
   ObjectSetString(0,  subName, OBJPROP_FONT,      "Consolas");
   ObjectSetInteger(0, subName, OBJPROP_FONTSIZE,  9);
   ObjectSetInteger(0, subName, OBJPROP_COLOR,     clrSilver);
   ObjectSetInteger(0, subName, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, subName, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, subName, OBJPROP_YDISTANCE, 42);
   ObjectSetInteger(0, subName, OBJPROP_ANCHOR,    ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, subName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, subName, OBJPROP_HIDDEN,    true);

   ChartRedraw();
  }

//=============================================================================
// MASTER DRAW FUNCTION
//=============================================================================
void DrawAll()
  {
   // Step 1 – Clean previous objects
   DeleteAllObjects();

   // Step 2 – Trading day filter
   bool tradingAllowed = IsTradingDay();

   // Step 3 – MTF Alignment
   int  mnStatus = 0, wkStatus = 0, dyStatus = 0; // +1 bull, -1 bear, 0 neutral
   bool aligned  = false;
   bool bullAlign = false, bearAlign = false;
   GetMTFAlignment(mnStatus, wkStatus, dyStatus, aligned, bullAlign, bearAlign);

   // Step 4 – EQ Lines
   double eq1Price = 0, eq2Price = 0;
   GetEQLevels(eq1Price, eq2Price);
   DrawEQLines(eq1Price, eq2Price);

   // Step 5 – FEZ Rectangle
   if(InpShowFEZ && eq1Price != 0 && eq2Price != 0)
      DrawFEZ(eq1Price, eq2Price);

   // Step 6 – Dashboard labels (top-right)
   DrawDashboard(mnStatus, wkStatus, dyStatus, aligned, bullAlign, bearAlign, tradingAllowed);

   // Step 7 – Edge Scoring panel
   DrawEdgeScoring();

   ChartRedraw();
  }

//=============================================================================
// TRADING DAY FILTER
// Rule: No trade on the first week of the month, no trade on Mondays (GMT+3)
//=============================================================================
bool IsTradingDay()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   // Monday check (dow = 1)
   if(dt.day_of_week == 1)
      return false;

   // First week of the month: day 1–7
   if(dt.day <= 7)
      return false;

   return true;
  }

//=============================================================================
// MARUBOZU DETECTION
// Returns +1 = bullish marubozu, -1 = bearish marubozu, 0 = neither
// Condition: wicks are NOT more than InpMarubozuWickRatio times the body
//=============================================================================
int IsMarubozu(double open, double high, double low, double close)
  {
   double body      = MathAbs(close - open);
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;

   if(body <= 0) return 0; // doji – no body

   // Reject if any wick exceeds ratio * body
   if(upperWick > InpMarubozuWickRatio * body) return 0;
   if(lowerWick > InpMarubozuWickRatio * body) return 0;

   return (close >= open) ? 1 : -1;
  }

//=============================================================================
// MTF ALIGNMENT DETECTION
// Fetches MN, W1, D1 (yesterday) candles and checks marubozu alignment
//=============================================================================
void GetMTFAlignment(int &mnStatus, int &wkStatus, int &dyStatus,
                     bool &aligned, bool &bullAlign, bool &bearAlign)
  {
   // --- Monthly candle (index 0 = current forming month) ---
   double mn_o = iOpen(NULL,  PERIOD_MN1, 0);
   double mn_h = iHigh(NULL,  PERIOD_MN1, 0);
   double mn_l = iLow(NULL,   PERIOD_MN1, 0);
   double mn_c = iClose(NULL, PERIOD_MN1, 0);
   mnStatus = IsMarubozu(mn_o, mn_h, mn_l, mn_c);
   // If current MN not yet conclusive, also check last closed MN (index 1)
   if(mnStatus == 0)
     {
      mn_o = iOpen(NULL,  PERIOD_MN1, 1);
      mn_h = iHigh(NULL,  PERIOD_MN1, 1);
      mn_l = iLow(NULL,   PERIOD_MN1, 1);
      mn_c = iClose(NULL, PERIOD_MN1, 1);
      mnStatus = IsMarubozu(mn_o, mn_h, mn_l, mn_c);
     }

   // --- Weekly candle (index 0 = current forming week) ---
   double wk_o = iOpen(NULL,  PERIOD_W1, 0);
   double wk_h = iHigh(NULL,  PERIOD_W1, 0);
   double wk_l = iLow(NULL,   PERIOD_W1, 0);
   double wk_c = iClose(NULL, PERIOD_W1, 0);
   wkStatus = IsMarubozu(wk_o, wk_h, wk_l, wk_c);
   if(wkStatus == 0)
     {
      wk_o = iOpen(NULL,  PERIOD_W1, 1);
      wk_h = iHigh(NULL,  PERIOD_W1, 1);
      wk_l = iLow(NULL,   PERIOD_W1, 1);
      wk_c = iClose(NULL, PERIOD_W1, 1);
      wkStatus = IsMarubozu(wk_o, wk_h, wk_l, wk_c);
     }

   // --- Daily: Yesterday candle (index 1 on D1) ---
   double dy_o = iOpen(NULL,  PERIOD_D1, 1);
   double dy_h = iHigh(NULL,  PERIOD_D1, 1);
   double dy_l = iLow(NULL,   PERIOD_D1, 1);
   double dy_c = iClose(NULL, PERIOD_D1, 1);
   dyStatus = IsMarubozu(dy_o, dy_h, dy_l, dy_c);

   // --- Alignment logic ---
   bullAlign = (mnStatus == 1 && wkStatus == 1 && dyStatus == 1);
   bearAlign = (mnStatus == -1 && wkStatus == -1 && dyStatus == -1);
   aligned   = (bullAlign || bearAlign);
  }

//=============================================================================
// EQ LEVELS
// EQ1 = Yesterday D1 open price
// EQ2 = Today D1 open price
//=============================================================================
void GetEQLevels(double &eq1, double &eq2)
  {
   eq1 = iOpen(NULL, PERIOD_D1, 1); // Yesterday open
   eq2 = iOpen(NULL, PERIOD_D1, 0); // Today open
  }

//=============================================================================
// DRAW EQ HORIZONTAL LINES
//=============================================================================
void DrawEQLines(double eq1, double eq2)
  {
   if(InpShowEQ1 && eq1 != 0)
      CreateHLine(PREFIX_EQ + "EQ1", eq1, InpEQColor, InpEQLineWidth, InpEQStyle, "EQ1");

   if(InpShowEQ2 && eq2 != 0)
      CreateHLine(PREFIX_EQ + "EQ2", eq2, InpEQColor, InpEQLineWidth, InpEQStyle, "EQ2");
  }

//+------------------------------------------------------------------+
//| Helper: create a labelled horizontal line                         |
//+------------------------------------------------------------------+
void CreateHLine(string name, double price, color clr, int width,
                 ENUM_LINE_STYLE style, string labelText)
  {
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,     width);
   ObjectSetInteger(0, name, OBJPROP_STYLE,     style);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,    true);
   ObjectSetString(0,  name, OBJPROP_TOOLTIP,   labelText + " = " + DoubleToString(price, _Digits));

   // Small label at the right of the line
   string lblName = name + "_LBL";
   if(ObjectFind(0, lblName) >= 0) ObjectDelete(0, lblName);

   datetime labelTime = TimeCurrent();
   ObjectCreate(0, lblName, OBJ_TEXT, 0, labelTime, price);
   ObjectSetString(0,  lblName, OBJPROP_TEXT,      " " + labelText);
   ObjectSetString(0,  lblName, OBJPROP_FONT,      InpLabelFont);
   ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE,  8);
   ObjectSetInteger(0, lblName, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, lblName, OBJPROP_ANCHOR,    ANCHOR_LEFT);
   ObjectSetInteger(0, lblName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, lblName, OBJPROP_HIDDEN,    true);
  }

//=============================================================================
// DRAW FEZ RECTANGLE (Focus Entry Zone)
// Frames the PREVIOUS day's session between EQ1 and EQ2 — no fill, gold border
//=============================================================================
void DrawFEZ(double eq1, double eq2)
  {
   if(!InpShowFEZ) return;

   string name = PREFIX_FEZ + "RECT";
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);

   // Previous day boundaries: D1[1] open → D1[0] open (exact bar timestamps)
   datetime dayStart = iTime(NULL, PERIOD_D1, 1); // yesterday open time
   datetime dayEnd   = iTime(NULL, PERIOD_D1, 0); // today open time = yesterday close boundary

   double top    = MathMax(eq1, eq2);
   double bottom = MathMin(eq1, eq2);

   ObjectCreate(0, name, OBJ_RECTANGLE, 0, dayStart, top, dayEnd, bottom);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     InpFEZColor);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,     InpFEZLineWidth);
   ObjectSetInteger(0, name, OBJPROP_FILL,      false);
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,    true);
   ObjectSetString(0,  name, OBJPROP_TOOLTIP,   "Focus Entry Zone (FEZ) – Previous Day");
  }

//=============================================================================
// DASHBOARD – Top-right labels
// Shows: Trading day status, Alignment status, MTF candle status
//=============================================================================
void DrawDashboard(int mnStatus, int wkStatus, int dyStatus,
                   bool aligned, bool bullAlign, bool bearAlign,
                   bool tradingAllowed)
  {
   int yOffset = 20; // starting Y position
   int lineH   = 20; // line height in pixels

   // ── Row 0: Trading Day Filter ─────────────────────────────────────
   string dayText  = tradingAllowed ? "TRADING DAY ✅" : "NO TRADE DAY ❌";
   color  dayColor = tradingAllowed ? clrLime : clrOrangeRed;
   CreateLabel(PREFIX_LBL + "DayFilter", dayText, CORNER_RIGHT_UPPER,
               LABEL_X, yOffset, InpLabelFontSize + 1, dayColor);
   yOffset += lineH + 4;

   // ── Row 1: MTF Alignment ──────────────────────────────────────────
   string alignText;
   color  alignColor;
   if(bullAlign)
     { alignText = "Bullishly Aligned ✅"; alignColor = clrLime; }
   else if(bearAlign)
     { alignText = "Bearishly Aligned ✅"; alignColor = clrOrangeRed; }
   else
     { alignText = "Not Aligned ❌";       alignColor = clrSilver; }

   CreateLabel(PREFIX_LBL + "Align", alignText, CORNER_RIGHT_UPPER,
               LABEL_X, yOffset, InpLabelFontSize, alignColor);
   yOffset += lineH;

   // ── Row 2: Per-TF candle status ───────────────────────────────────
   string mnTxt = StatusText(mnStatus);
   string wkTxt = StatusText(wkStatus);
   string dyTxt = StatusText(dyStatus);
   string tfLine = "MN: " + mnTxt + "  |  WK: " + wkTxt + "  |  D: " + dyTxt;

   color tfColor = clrWhiteSmoke;
   CreateLabel(PREFIX_LBL + "TFStatus", tfLine, CORNER_RIGHT_UPPER,
               LABEL_X, yOffset, InpLabelFontSize - 1, tfColor);
  }

//+------------------------------------------------------------------+
//| Helper: status text from integer                                  |
//+------------------------------------------------------------------+
string StatusText(int status)
  {
   if(status ==  1) return "UP";
   if(status == -1) return "DOWN";
   return "—";
  }

//=============================================================================
// EDGE SCORING PANEL – Bottom-right corner
// Checklist: 6 criteria, max 11 pts, need ≥ 8 to trade
//=============================================================================
void DrawEdgeScoring()
  {
   int lineH = 18;
   int row   = 0;

   // Total rows = 1 header + 6 criteria + 1 score + 1 verdict = 9 rows
   // We anchor from CORNER_RIGHT_LOWER, so row 0 = bottom, counting upward.
   // We reverse the draw order so the header appears at the top visually.
   int totalRows = 9;

   // ── GO / NO TRADE verdict – drawn at the very bottom (row 0) ─────
   int total = 0;
   total += InpEdge_Alignment    ? 2 : 0;
   total += InpEdge_StrongMedium ? 2 : 0;
   total += InpEdge_IntermMedium ? 1 : 0;
   total += InpEdge_BaseNumber   ? 2 : 0;
   total += InpEdge_RR           ? 2 : 0;
   total += InpEdge_FreshZone    ? 2 : 0;

   string verdict = (total >= 8) ? "GO TRADE ✅" : "NO TRADE ❌";
   color  vColor  = (total >= 8) ? clrLime : clrOrangeRed;
   CreateLabel(PREFIX_LBL + "Verdict", verdict, CORNER_RIGHT_LOWER,
               LABEL_X, 20 + (row++ * lineH), InpLabelFontSize + 2, vColor);

   // ── Total score ───────────────────────────────────────────────────
   string scoreText  = "Score: " + IntegerToString(total) + "/11";
   color  scoreColor = (total >= 8) ? clrLime : clrOrangeRed;
   CreateLabel(PREFIX_LBL + "ScoreTotal", scoreText, CORNER_RIGHT_LOWER,
               LABEL_X, 20 + (row++ * lineH), InpLabelFontSize, scoreColor);

   // ── Individual criteria (drawn bottom-up = reversed order) ────────
   DrawScoreLine("SC_Fresh",   "Fresh Zone",          InpEdge_FreshZone,    2, row++, lineH);
   DrawScoreLine("SC_RR",      "RR 1/3 Min",          InpEdge_RR,           2, row++, lineH);
   DrawScoreLine("SC_Base",    "Base Number < 5",     InpEdge_BaseNumber,   2, row++, lineH);
   DrawScoreLine("SC_IntMed",  "Intermediate Momentum", InpEdge_IntermMedium, 1, row++, lineH);
   DrawScoreLine("SC_StMed",   "Strong Momentum",       InpEdge_StrongMedium, 2, row++, lineH);
   DrawScoreLine("SC_Align",   "Alignment",           InpEdge_Alignment,    2, row++, lineH);

   // ── Section header – topmost (highest row index) ──────────────────
   CreateLabel(PREFIX_LBL + "ScoreHdr", "── DTE Edge Scoring ──",
               CORNER_RIGHT_LOWER, LABEL_X, 20 + (row * lineH),
               InpLabelFontSize, clrGold);
  }

//+------------------------------------------------------------------+
//| Draw a single score line in the bottom-right panel               |
//+------------------------------------------------------------------+
void DrawScoreLine(string id, string criterion, bool met,
                   int maxPts, int row, int lineH)
  {
   string checkMark = met ? "✅" : "☐";
   string text = checkMark + " " + criterion + "  +" + IntegerToString(maxPts);
   color  clr  = met ? clrLime : clrDimGray;

   CreateLabel(PREFIX_LBL + id, text, CORNER_RIGHT_LOWER,
               LABEL_X, 20 + (row * lineH),
               InpLabelFontSize - 1, clr);
  }

//=============================================================================
// HELPER: Create a screen-space label (OBJ_LABEL)
//=============================================================================
void CreateLabel(string name,      string text,
                 ENUM_BASE_CORNER corner,
                 int xDist,        int yDist,
                 int fontSize,     color clr)
  {
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0,  name, OBJPROP_TEXT,     text);
   ObjectSetString(0,  name, OBJPROP_FONT,     InpLabelFont);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR,    clr);
   ObjectSetInteger(0, name, OBJPROP_CORNER,   corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, xDist);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, yDist);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,   ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,   true);
  }

//=============================================================================
// CLEANUP: Delete all objects created by this indicator
//=============================================================================
void DeleteAllObjects()
  {
   DeleteByPrefix(PREFIX_EQ);
   DeleteByPrefix(PREFIX_FEZ);
   DeleteByPrefix(PREFIX_LBL);
  }

void DeleteByPrefix(string prefix)
  {
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
     }
  }

//+------------------------------------------------------------------+
//| Chart events (optional – for future interactivity)               |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long   &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(id == CHARTEVENT_CHART_CHANGE)
      DrawAll();
  }
//+------------------------------------------------------------------+
//                       END OF INDICATOR                             //
//+------------------------------------------------------------------+
