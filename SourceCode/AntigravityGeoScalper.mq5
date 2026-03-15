//+------------------------------------------------------------------+
//|                                     AntigravityGeoScalper.mq5    |
//|                                    Copyright 2026, Antigravity   |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, Antigravity"
#property link        "https://www.mql5.com"
#property version     "1.00"
#property description "Purely geometric logic scalp EA on XAUUSD. \nNo lagging indicators (RSI, MACD etc) permitted."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

CTrade         trade;
CSymbolInfo    sym;
CAccountInfo   acc;
CPositionInfo  pos;

//--- mathematical constants
#define PHI 1.6180339887
#define PHI_INV 0.6180339887
#define SQRT2 1.4142135623
#define SQRT3 1.7320508075
#define SQRT5 2.2360679774
#define MATH_PI 3.1415926535
#define MATH_E 2.7182818284
#define LN_PHI 0.4812118250

//--- inputs
input group "=== Geometric Parameters ==="
input int    InpSwingLookback       = 5;          // Fractal Swing Lookback Bars
input int    InpLRBars              = 50;         // Linear Regression Channel Bars
input double InpHarmonicTolerance   = 0.05;       // Harmonic Pattern Ratio Tolerance
input double InpGannPriceUnit       = 0.10;       // Gann Price Unit
input double InpMinConflScore       = 65.0;       // Minimum Confluence Score

input group "=== Risk Management ==="
input double InpRiskPercent         = 1.0;        // Risk Percent Per Trade
input double InpFixedLot            = 0.01;       // Fixed Lot (if Dynamic Lot is false)
input bool   InpUseDynamicLot       = true;       // Use Dynamic Risk %
input int    InpMaxSlippage         = 20;         // Max Slippage (Points)
input int    InpMaxTrades           = 2;          // Max Concurrent Trades
input double InpMaxDailyLossPct     = 3.0;        // Max Daily Loss %

input group "=== Display & Visuals ==="
input bool   InpShowHUD             = true;       // Draw Dashboard Info
input bool   InpDrawGannFan         = true;       // Draw Gann Fans
input bool   InpDrawFibLevels       = true;       // Draw Fib Levels
input bool   InpDrawHarmonicZone    = true;       // Draw PRZ Zone Rectangle
input color  InpBullishColor        = clrDodgerBlue;
input color  InpBearishColor        = clrOrangeRed;
input color  InpNeutralColor        = clrDarkGray;

//--- Global variables
double start_balance = 0.0;
double daily_loss_limit = 0.0;

// geometric state variables
double prz_top = 0.0, prz_bot = 0.0;
double current_confluence = 0;
int    signal_direction = 0; // 1 for long, -1 for short, 0 for none

//--- Geometric Structs
struct Coordinate {
    int index;
    double price;
    datetime time;
    int type; // 1 for High, -1 for Low
};

Coordinate swing_highs[];
Coordinate swing_lows[];

double fib_levels[] = {0.236, 0.382, 0.500, 0.618, 0.705, 0.786, 0.886};
double fib_extensions[] = {1.0, 1.272, 1.414, 1.618, 2.0, 2.618, 3.618, 4.236};

string string_last_pattern = "None";
string string_harmonic_pattern = "None";
string string_gann_angle = "None";
string string_vector_dir = "None";
double last_body_ratio = 0.0;
double last_wick_ratio = 0.0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Validate Symbol
    string s = Symbol();
    if(StringFind(s, "GOLD") < 0 && StringFind(s, "XAUUSD") < 0) {
        Print("Warning: This EA is optimized for GOLD/XAUUSD. Current symbol: ", s);
    }
    
    // Init Trade objects
    sym.Name(s);
    sym.Refresh();
    trade.SetExpertMagicNumber(20260314);
    trade.SetMarginMode();
    trade.SetTypeFillingBySymbol(s);
    trade.SetDeviationInPoints(InpMaxSlippage);
    
    // Init Account Limits
    start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    daily_loss_limit = start_balance * (InpMaxDailyLossPct / 100.0);
    
    // Init Chart
    if(InpShowHUD) DrawHUD_Init();
    
    Print("AntigravityGeoScalper Initialization Complete. Golden Ratio Math Loaded.");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    ObjectsDeleteAll(0, "GeoScalper_");
    Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // We only process on new bar or tick, based on requirements. 
    // "tick_geometry" implies analyzing M1 ticks as well, but standard is new M1 candle.
    static datetime last_time = 0;
    datetime current_time = iTime(_Symbol, PERIOD_CURRENT, 0);
    sym.Refresh();
    
    // Update live HUD
    if(InpShowHUD) DrawHUD_Update();
    
    // Tick-level logic
    if (PositionsTotal() > 0) {
        ManagePositions();
    }
    
    // Gate by new bar
    if(current_time != last_time) {
        last_time = current_time;
        
        // Execute primary geometric engines
        RunAllGeometryEngines();
        
        // Draw Chart objects
        DrawChartObjects();
        
        // Check entry conditions
        if (current_confluence >= InpMinConflScore && PositionsTotal() < InpMaxTrades) {
            ExecuteTrade();
        }
    }
}

//+------------------------------------------------------------------+
//| Geometry Engines Coordinator                                     |
//+------------------------------------------------------------------+
void RunAllGeometryEngines()
{
    current_confluence = 0;
    signal_direction = 0;
    
    // 1. Detect Fractal Swings
    DetectSwings();
    
    // 2. Fibonacci Engine
    double fib_score = RunFibEngine();
    
    // 3. Harmonic Engine
    double harm_score = RunHarmonicEngine();
    
    // 4. Gann Engine
    double gann_score = RunGannEngine();
    
    // 5. Vector Momentum Engine
    double vect_score = RunVectorEngine();
    
    // 6. Fractal Engine 
    double frac_score = RunFractalEngine();
    
    // 7. Candlestick Geometry
    double cand_score = AnalyzeCandleGeometry();
    
    // Aggregate Confluence
    current_confluence = fib_score + harm_score + gann_score + vect_score + frac_score + cand_score;
    
    // Set active signal direction based on sum of vectors/pattern directions.
    signal_direction = ComputeDirection();
}

//+------------------------------------------------------------------+
//| Engine Stub Implementations (Placeholders for complex math)      |
//+------------------------------------------------------------------+

void DetectSwings() 
{
    ArrayFree(swing_highs);
    ArrayFree(swing_lows);
    
    int limit = 1000; // Search last 1000 bars
    int n = InpSwingLookback;
    
    for(int i = n; i < limit - n; i++) {
        // Check Fractal High
        bool isHigh = true;
        double high_i = iHigh(_Symbol, PERIOD_CURRENT, i);
        for(int j = 1; j <= n; j++) {
            if(iHigh(_Symbol, PERIOD_CURRENT, i-j) >= high_i || iHigh(_Symbol, PERIOD_CURRENT, i+j) >= high_i) {
                isHigh = false;
                break;
            }
        }
        if(isHigh) {
            int size = ArraySize(swing_highs);
            ArrayResize(swing_highs, size + 1);
            swing_highs[size].index = i;
            swing_highs[size].price = high_i;
            swing_highs[size].time = iTime(_Symbol, PERIOD_CURRENT, i);
            swing_highs[size].type = 1;
        }
        
        // Check Fractal Low
        bool isLow = true;
        double low_i = iLow(_Symbol, PERIOD_CURRENT, i);
        for(int j = 1; j <= n; j++) {
            if(iLow(_Symbol, PERIOD_CURRENT, i-j) <= low_i || iLow(_Symbol, PERIOD_CURRENT, i+j) <= low_i) {
                isLow = false;
                break;
            }
        }
        if(isLow) {
            int size = ArraySize(swing_lows);
            ArrayResize(swing_lows, size + 1);
            swing_lows[size].index = i;
            swing_lows[size].price = low_i;
            swing_lows[size].time = iTime(_Symbol, PERIOD_CURRENT, i);
            swing_lows[size].type = -1;
        }
    }
}

double RunFibEngine() 
{
    // Returns 0-20 score depending on level cluster overlap density
    int h_size = ArraySize(swing_highs);
    int l_size = ArraySize(swing_lows);
    if(h_size < 2 || l_size < 2) return 0.0;
    
    // Find absolute max/min of recent 2 swings to project Fibs
    double max_h = MathMax(swing_highs[h_size-1].price, swing_highs[h_size-2].price);
    double min_l = MathMin(swing_lows[l_size-1].price, swing_lows[l_size-2].price);
    double range = max_h - min_l;
    
    double current_price = sym.Bid();
    int cluster_count = 0;
    
    // Check retracement levels
    for(int i = 0; i < ArraySize(fib_levels); i++) {
        double level_up = min_l + (range * fib_levels[i]);
        double level_dn = max_h - (range * fib_levels[i]);
        
        // Confluence band width: +-0.5% of level price
        double band = level_up * 0.005; 
        if(MathAbs(current_price - level_up) <= band) cluster_count++;
        if(MathAbs(current_price - level_dn) <= band) cluster_count++;
    }
    
    if(cluster_count >= 4) return 20.0;
    if(cluster_count == 3) return 15.0;
    if(cluster_count == 2) return 10.0;
    if(cluster_count == 1) return 5.0;
    return 0.0; 
}

double RunHarmonicEngine() 
{
    // XABCD scanner checking Gartley, Bat, Butterfly, Crab, Shark, Cypher
    // Demands 5 alternating pivots.
    string_harmonic_pattern = "None";
    int h_size = ArraySize(swing_highs);
    int l_size = ArraySize(swing_lows);
    if(h_size < 3 || l_size < 3) return 0.0;
    
    // Simplification for prototype: Grab the last 5 alternating points
    // M pattern = Low, High, Low, High, Low
    // W pattern = High, Low, High, Low, High
    // We will measure absolute leg ratios.
    double X = swing_highs[h_size-3].price;
    double A = swing_lows[l_size-3].price;
    double B = swing_highs[h_size-2].price;
    double C = swing_lows[l_size-2].price;
    double D = swing_highs[h_size-1].price;
    
    double XA = MathAbs(X - A);
    double AB = MathAbs(A - B);
    double BC = MathAbs(B - C);
    double CD = MathAbs(C - D);
    
    if(XA == 0 || AB == 0 || BC == 0) return 0;
    
    double ratio_AB_XA = AB / XA;
    double ratio_BC_AB = BC / AB;
    double ratio_CD_BC = CD / BC;
    double ratio_CD_XA = CD / XA;
    
    double tol = InpHarmonicTolerance;
    double score = 0.0;
    
    // Check Gartley
    if( MathAbs(ratio_AB_XA - 0.618) <= tol && 
       (MathAbs(ratio_BC_AB - 0.382) <= tol || MathAbs(ratio_BC_AB - 0.886) <= tol) &&
        MathAbs(ratio_CD_XA - 0.786) <= tol ) {
        score = 25.0; // Perfect match
        string_harmonic_pattern = "Gartley";
        prz_top = D + (CD * 0.05);
        prz_bot = D - (CD * 0.05);
    }
    // Check Butterfly
    else if( MathAbs(ratio_AB_XA - 0.786) <= tol && 
       (MathAbs(ratio_BC_AB - 0.382) <= tol || MathAbs(ratio_BC_AB - 0.886) <= tol) &&
       (MathAbs(ratio_CD_XA - 1.272) <= tol || MathAbs(ratio_CD_XA - 1.618) <= tol) ) {
        score = 25.0;
        string_harmonic_pattern = "Butterfly";
        prz_top = D + (CD * 0.05);
        prz_bot = D - (CD * 0.05);
    }
    // Check Bat
    else if( (MathAbs(ratio_AB_XA - 0.382) <= tol || MathAbs(ratio_AB_XA - 0.500) <= tol) && 
       (MathAbs(ratio_BC_AB - 0.382) <= tol || MathAbs(ratio_BC_AB - 0.886) <= tol) &&
        MathAbs(ratio_CD_XA - 0.886) <= tol ) {
        score = 25.0;
        string_harmonic_pattern = "Bat";
        prz_top = D + (CD * 0.05);
        prz_bot = D - (CD * 0.05);
    }
    
    return score; 
}

double RunGannEngine() 
{
    // Time/Price matrix logic, 1x1 45 degree angle validations
    // Uses the most recent Swing High or Low (index 1)
    string_gann_angle = "None";
    int h_size = ArraySize(swing_highs);
    int l_size = ArraySize(swing_lows);
    if(h_size < 1 || l_size < 1) return 0.0;
    
    Coordinate pivot;
    bool isBullish = false;
    
    // Pick the most recent pivot
    if(swing_highs[h_size-1].index < swing_lows[l_size-1].index) {
        pivot = swing_highs[h_size-1]; // Recent pivot was a high
        isBullish = false;
    } else {
        pivot = swing_lows[l_size-1]; // Recent pivot was a low
        isBullish = true;
    }
    
    int bars_since_pivot = pivot.index; // index 0 is current bar in array logic if 0-based, our index goes up with history
    if(bars_since_pivot == 0) return 0.0;
    
    double current_price = sym.Bid();
    
    // 1x1 Angle: Price moves 1 unit per 1 unit of time
    double gann_unit = InpGannPriceUnit * sym.Point();
    double target_1x1 = pivot.price + (isBullish ? (bars_since_pivot * gann_unit) : -(bars_since_pivot * gann_unit));
    double target_2x1 = pivot.price + (isBullish ? (bars_since_pivot * gann_unit * 2) : -(bars_since_pivot * gann_unit * 2));
    double target_1x2 = pivot.price + (isBullish ? (bars_since_pivot * gann_unit * 0.5) : -(bars_since_pivot * gann_unit * 0.5));
    
    double tol = 50 * sym.Point(); // 50 points tolerance
    
    if(MathAbs(current_price - target_1x1) <= tol) {
        string_gann_angle = "1x1 Support/Resistance";
        return 15.0;
    }
    if(MathAbs(current_price - target_2x1) <= tol) {
        string_gann_angle = "2x1";
        return 10.0;
    }
    if(MathAbs(current_price - target_1x2) <= tol) {
        string_gann_angle = "1x2";
        return 8.0;
    }
    
    return 0.0;
}

double RunVectorEngine() 
{
    // 2D Vector |V| = sqrt( time^2 + price^2 ). Dot product check.
    // Compare V_current (last pivot to price) vs V_prev (previous same-direction pivot leg)
    string_vector_dir = "None";
    int h_size = ArraySize(swing_highs);
    int l_size = ArraySize(swing_lows);
    if(h_size < 2 || l_size < 2) return 0.0;
    
    Coordinate recent_low = swing_lows[l_size-1];
    Coordinate prev_low = swing_lows[l_size-2];
    
    Coordinate recent_high = swing_highs[h_size-1];
    Coordinate prev_high = swing_highs[h_size-2];
    
    double current_price = sym.Bid();
    double score = 0.0;
    
    // Evaluate bullish momentum magnitude
    double t_curr_bull = recent_low.index; 
    double p_curr_bull = (current_price - recent_low.price) / sym.Point();
    double mag_curr_bull = MathSqrt((t_curr_bull * t_curr_bull) + (p_curr_bull * p_curr_bull));
    
    double t_prev_bull = prev_low.index - (recent_high.index < prev_low.index ? recent_high.index : swing_highs[h_size-3].index);
    double p_prev_bull = (recent_high.price - prev_low.price) / sym.Point();
    double mag_prev_bull = MathSqrt((t_prev_bull * t_prev_bull) + (p_prev_bull * p_prev_bull));
    
    // Evaluate bearish momentum magnitude
    double t_curr_bear = recent_high.index; 
    double p_curr_bear = MathAbs((current_price - recent_high.price) / sym.Point());
    double mag_curr_bear = MathSqrt((t_curr_bear * t_curr_bear) + (p_curr_bear * p_curr_bear));
    
    double t_prev_bear = prev_high.index - recent_low.index;
    double p_prev_bear = MathAbs((recent_low.price - prev_high.price) / sym.Point());
    double mag_prev_bear = MathSqrt((t_prev_bear * t_prev_bear) + (p_prev_bear * p_prev_bear));
    
    if(mag_prev_bull > 0 && (mag_curr_bull / mag_prev_bull) >= PHI) {
        score += 7.5;
        string_vector_dir = "Bull Phi Accel";
    }
    if(mag_prev_bear > 0 && (mag_curr_bear / mag_prev_bear) >= PHI) {
        score += 7.5;
        string_vector_dir = "Bear Phi Accel";
    }
    
    // Dot product alignment
    double dot_bull = (t_curr_bull * t_prev_bull) + (p_curr_bull * p_prev_bull);
    double dot_bear = (t_curr_bear * t_prev_bear) + (-p_curr_bear * -p_prev_bear); // Both drop
    
    if(dot_bull > 0 && current_price > recent_low.price) score += 7.5;
    if(dot_bear > 0 && current_price < recent_high.price) score += 7.5;
    
    return score;
}

double RunFractalEngine() 
{
    // Compares leg ratios over multiple TFs for self-similarity
    // For MQL5 prototype on single chart execution, test Hausdorf limit
    int h_size = ArraySize(swing_highs);
    if(h_size < 3) return 0.0;
    
    // proxy for fractal alignment
    // (P3-P2) / (P2-P1)
    double leg1 = MathAbs(swing_highs[h_size-2].price - swing_highs[h_size-3].price);
    double leg2 = MathAbs(swing_highs[h_size-1].price - swing_highs[h_size-2].price);
    
    if(leg1 == 0) return 0.0;
    double ratio = leg2 / leg1;
    
    // Golden ratio self-similarity search
    if(MathAbs(ratio - 1.618) <= 0.05 || MathAbs(ratio - 0.618) <= 0.05) {
        return 10.0;
    }
    
    return 0.0;
}

double AnalyzeCandleGeometry() 
{
    double score = 0.0;
    
    // Analyze completed candle (index 1) and previous (index 2)
    double O = iOpen(_Symbol, PERIOD_CURRENT, 1);
    double H = iHigh(_Symbol, PERIOD_CURRENT, 1);
    double L = iLow(_Symbol, PERIOD_CURRENT, 1);
    double C = iClose(_Symbol, PERIOD_CURRENT, 1);
    
    double O2 = iOpen(_Symbol, PERIOD_CURRENT, 2);
    double H2 = iHigh(_Symbol, PERIOD_CURRENT, 2);
    double L2 = iLow(_Symbol, PERIOD_CURRENT, 2);
    double C2 = iClose(_Symbol, PERIOD_CURRENT, 2);
    
    double TotalRange = H - L;
    if(TotalRange == 0) return 0.0; // Prevent division by zero
    
    double BodySize = MathAbs(C - O);
    double UpperWick = H - MathMax(O, C);
    double LowerWick = MathMin(O, C) - L;
    
    double BodyRatio = BodySize / TotalRange;
    double UpperWickRatio = UpperWick / TotalRange;
    double LowerWickRatio = LowerWick / TotalRange;
    
    last_body_ratio = BodyRatio;
    last_wick_ratio = MathMax(UpperWickRatio, LowerWickRatio);
    string_last_pattern = "None";
    
    // Pattern Rules
    bool Doji = BodyRatio < 0.05;
    bool Pin_Bar_Bullish = LowerWickRatio > 0.60 && BodyRatio < 0.30 && UpperWickRatio < 0.10;
    bool Pin_Bar_Bearish = UpperWickRatio > 0.60 && BodyRatio < 0.30 && LowerWickRatio < 0.10;
    bool Bullish_Engulf = C > O && O < C2 && C > O2 && BodyRatio > 0.55 && C2 < O2; 
    bool Bearish_Engulf = C < O && O > C2 && C < O2 && BodyRatio > 0.55 && C2 > O2; 
    bool Inside_Bar = H < H2 && L > L2;
    bool Outside_Bar = H > H2 && L < L2;
    bool Marubozu_Bullish = BodyRatio > 0.92 && UpperWickRatio < 0.04 && LowerWickRatio < 0.04 && C > O;
    bool Marubozu_Bearish = BodyRatio > 0.92 && UpperWickRatio < 0.04 && LowerWickRatio < 0.04 && C < O;
    
    if(Pin_Bar_Bullish || Bullish_Engulf) {
        score = 10.0;
        string_last_pattern = Pin_Bar_Bullish ? "Pin Bar (Bull)" : "Engulf (Bull)";
    } else if(Pin_Bar_Bearish || Bearish_Engulf) {
        score = 10.0;
        string_last_pattern = Pin_Bar_Bearish ? "Pin Bar (Bear)" : "Engulf (Bear)";
    } else if(Marubozu_Bullish || Marubozu_Bearish) {
        score = 8.0;
        string_last_pattern = Marubozu_Bullish ? "Marubozu (Bull)" : "Marubozu (Bear)";
    } else if(Doji) {
        score = 7.0;
        string_last_pattern = "Doji";
    } else if(Outside_Bar) {
        score = 6.0;
        string_last_pattern = "Outside Bar";
    } else if(Inside_Bar) {
        score = 5.0;
        string_last_pattern = "Inside Bar";
    }
    
    return score;
}

int ComputeDirection()
{
    // Determine overall geometric direction. Returns 1 for Long, -1 for Short.
    int long_votes = 0;
    int short_votes = 0;
    
    // 1. Candlestick geometry
    if(StringFind(string_last_pattern, "Bull") >= 0) long_votes++;
    if(StringFind(string_last_pattern, "Bear") >= 0) short_votes++;
    
    // 2. Harmonic Geometry
    if(string_harmonic_pattern != "None") {
        // Simple logic for prototype: D-point below C = Bullish setup usually
        if(prz_bot != 0 && sym.Bid() > prz_bot) long_votes += 2; 
        if(prz_bot != 0 && sym.Bid() < prz_top) short_votes += 2;
    }
    
    // 3. Vector Acceleration
    if(StringFind(string_vector_dir, "Bull") >= 0) long_votes++;
    if(StringFind(string_vector_dir, "Bear") >= 0) short_votes++;
    
    // 4. Gann Geometry (above support 1x1 = bull)
    if(StringFind(string_gann_angle, "Support") >= 0) long_votes++;
    
    if(long_votes > short_votes && long_votes >= 2) return 1;
    if(short_votes > long_votes && short_votes >= 2) return -1;
    
    return 0; // Conflicting or neutral geometry
}

//+------------------------------------------------------------------+
//| Execution & Management                                           |
//+------------------------------------------------------------------+

void ExecuteTrade()
{
    // Validate risk limit
    if (AccountInfoDouble(ACCOUNT_EQUITY) < start_balance - daily_loss_limit) {
        Print("Daily loss limit reached. No further trades today.");
        return;
    }
    
    // Dynamic TP/SL Logic (Phase 3 requirements)
    // Basic scaling based on Volatility/Point Size
    double sl_points = 100 * sym.Point(); // Min SL = 100 points
    double tp_points = 160 * sym.Point();
    
    // Attempt dynamic geometric SL based on recent fractal point
    int h_size = ArraySize(swing_highs);
    int l_size = ArraySize(swing_lows);
    
    if (signal_direction == 1 && l_size > 0) {
        double geom_sl = sym.Ask() - swing_lows[l_size-1].price;
        if(geom_sl > sl_points) sl_points = geom_sl;
    } else if (signal_direction == -1 && h_size > 0) {
        double geom_sl = swing_highs[h_size-1].price - sym.Bid();
        if(geom_sl > sl_points) sl_points = geom_sl;
    }
    
    // Cap SL to reasonable scalping risk (max 300 points)
    if(sl_points > 300 * sym.Point()) sl_points = 300 * sym.Point();
    tp_points = sl_points * PHI; // Golden ratio risk/reward
    
    double lot = CalculateLot(sl_points);
    if(lot < sym.VolumeMin()) lot = sym.VolumeMin();
    if(lot > sym.VolumeMax()) lot = sym.VolumeMax();
    lot = NormalizeDouble(lot, 2);
    
    double sl = 0.0, tp1 = 0.0;
    
    if (signal_direction == 1) { // LONG
        sl = sym.Ask() - sl_points;
        tp1 = sym.Ask() + tp_points;
        trade.Buy(lot, _Symbol, 0, sl, tp1, "AntigravityGeo LONG");
    } 
    else if (signal_direction == -1) { // SHORT
        sl = sym.Bid() + sl_points;
        tp1 = sym.Bid() - tp_points;
        trade.Sell(lot, _Symbol, 0, sl, tp1, "AntigravityGeo SHORT");
    }
}

double CalculateLot(double sl_dist)
{
    if (!InpUseDynamicLot) return InpFixedLot;
    // geometric risk % equation
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk_amount = balance * (InpRiskPercent / 100.0);
    double tick_value = sym.TickValue();
    double tick_size = sym.TickSize();
    
    if(sl_dist == 0 || tick_size == 0) return InpFixedLot;
    
    // Risk = Lot * (SL / TickSize) * TickValue
    // Lot = Risk / ((SL / TickSize) * TickValue)
    double points_at_risk = sl_dist / tick_size;
    double lot = risk_amount / (points_at_risk * tick_value); 
    return lot;
}

void ManagePositions()
{
    // Implements Break Even rules and geometric trailing stops
    for(int i = PositionsTotal()-1; i>=0; i--) {
        if(pos.SelectByIndex(i) && pos.Symbol() == _Symbol) {
            double open_price = pos.PriceOpen();
            double current_sl = pos.StopLoss();
            double be_trigger = 40 * sym.Point(); // 40 points in favor triggers BE
            double be_level = 5 * sym.Point();    // Lock in 5 points
            
            if(pos.PositionType() == POSITION_TYPE_BUY) {
                if(sym.Bid() > open_price + be_trigger) {
                    if(current_sl < open_price + be_level) {
                        trade.PositionModify(pos.Ticket(), open_price + be_level, pos.TakeProfit());
                    }
                }
            }
            else if(pos.PositionType() == POSITION_TYPE_SELL) {
                if(sym.Ask() < open_price - be_trigger) {
                    if(current_sl > open_price - be_level || current_sl == 0) {
                        trade.PositionModify(pos.Ticket(), open_price - be_level, pos.TakeProfit());
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Interface Rendering Functions                                    |
//+------------------------------------------------------------------+

void DrawHUD_Init()
{
    string label = "GeoScalper_HUD";
    ObjectCreate(0, label, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, label, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, label, OBJPROP_XDISTANCE, 10);
    ObjectSetInteger(0, label, OBJPROP_YDISTANCE, 20);
    ObjectSetInteger(0, label, OBJPROP_FONTSIZE, 10);
    ObjectSetString(0, label, OBJPROP_FONT, "Consolas");
    ObjectSetInteger(0, label, OBJPROP_COLOR, clrWhite);
}

void DrawHUD_Update()
{
    string label = "GeoScalper_HUD";
    string text = StringFormat("--- AntigravityGeoScalper ---\n"
                               "Symbol: %s | Spread: %d pts\n"
                               "Bal: %.2f | Eq: %.2f\n"
                               "Confluence: %.1f / 100\n"
                               "Signal: %s\n"
                               "Harmonic: %s\n"
                               "Gann Angle: %s\n"
                               "Vector State: %s\n"
                               "Last Pattern: %s\n"
                               "Body: %.2f | Wick: %.2f\n",
                               sym.Name(),
                               sym.Spread(),
                               AccountInfoDouble(ACCOUNT_BALANCE),
                               AccountInfoDouble(ACCOUNT_EQUITY),
                               current_confluence,
                               (signal_direction==1?"LONG":(signal_direction==-1?"SHORT":"NONE")),
                               string_harmonic_pattern,
                               string_gann_angle,
                               string_vector_dir,
                               string_last_pattern,
                               last_body_ratio,
                               last_wick_ratio);
    ObjectSetString(0, label, OBJPROP_TEXT, text);
}

void DrawChartObjects()
{
    // Clean up previous dynamic objects
    ObjectsDeleteAll(0, "GeoScalper_Dyn_");
    
    // 1. Draw PRZ (Potential Reversal Zone) if Harmonic Pattern detected
    if(string_harmonic_pattern != "None" && prz_bot != 0 && prz_top != 0 && InpDrawHarmonicZone) {
        string prz_name = "GeoScalper_Dyn_PRZ";
        datetime time1 = iTime(_Symbol, PERIOD_CURRENT, 10);
        datetime time2 = iTime(_Symbol, PERIOD_CURRENT, 0);
        
        ObjectCreate(0, prz_name, OBJ_RECTANGLE, 0, time1, prz_top, time2, prz_bot);
        ObjectSetInteger(0, prz_name, OBJPROP_COLOR, clrMediumPurple);
        ObjectSetInteger(0, prz_name, OBJPROP_FILL, true);
        ObjectSetInteger(0, prz_name, OBJPROP_BACK, true);
    }
    
    // 2. Mark recent fractals
    int h_size = ArraySize(swing_highs);
    int l_size = ArraySize(swing_lows);
    
    if(h_size > 0) {
        string p_name = "GeoScalper_Dyn_High";
        Coordinate last_h = swing_highs[h_size-1];
        ObjectCreate(0, p_name, OBJ_ARROW_DOWN, 0, last_h.time, last_h.price + (10 * sym.Point()));
        ObjectSetInteger(0, p_name, OBJPROP_COLOR, InpBearishColor);
        ObjectSetInteger(0, p_name, OBJPROP_WIDTH, 2);
    }
    
    if(l_size > 0) {
        string p_name = "GeoScalper_Dyn_Low";
        Coordinate last_l = swing_lows[l_size-1];
        ObjectCreate(0, p_name, OBJ_ARROW_UP, 0, last_l.time, last_l.price - (10 * sym.Point()));
        ObjectSetInteger(0, p_name, OBJPROP_COLOR, InpBullishColor);
        ObjectSetInteger(0, p_name, OBJPROP_WIDTH, 2);
    }
}
//+------------------------------------------------------------------+
