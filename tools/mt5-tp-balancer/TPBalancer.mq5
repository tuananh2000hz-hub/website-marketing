//+------------------------------------------------------------------+
//| TPBalancer.mq5                                                   |
//| Quan ly lenh vao tay (Magic = 0, khong comment):                 |
//|  - Gom lenh thanh chu ky (chuoi DCA cung chieu)                  |
//|  - Dong bo SL chung cho ca chuoi                                 |
//|  - Tinh TP chung sao cho Tong loi tai TP = Tong lo tai SL x RR   |
//|  - Gui so lieu len web (Google Apps Script) de theo doi online   |
//+------------------------------------------------------------------+
#property copyright "Tuan"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

input double InpRR               = 1.0;    // RR tong (1.0 = loi bang lo)
input double InpStartLot         = 0.01;   // Lot mo dau chu ky moi
input bool   InpOnlyEmptyComment = true;   // Chi quan ly lenh khong co comment
input bool   InpShowPanel        = true;   // Hien bang thong tin tren chart
input string InpWebUrl           = "";     // URL Web App (Google Apps Script)
input string InpWebKey           = "doi-ma-bi-mat-nay"; // Ma bi mat khop voi Apps Script
input int    InpPushSeconds      = 30;     // Chu ky gui du lieu len web (giay)

struct Pos
  {
   ulong    ticket;
   int      type;      // POSITION_TYPE_BUY / POSITION_TYPE_SELL
   long     timeMsc;
   double   vol;
   double   price;
   double   sl;
   double   tp;
   double   profit;
   int      cycle;
   bool     manual;    // anh da tu chinh TP -> EA khong dong vao TP nua
  };

CTrade   trade;
string   g_prefix;
datetime g_lastPush    = 0;
datetime g_lastCleanup = 0;
string   g_status      = "";

//--- cycle stats cho panel + web
int    s_cycle = 0, s_dir = -1, s_steps = 0;
double s_lots = 0, s_avg = 0, s_sl = 0, s_tp = 0, s_risk = 0, s_reward = 0, s_float = 0;

//+------------------------------------------------------------------+
//| Global variable helpers (luu trang thai qua khi tat/bat MT5)     |
//+------------------------------------------------------------------+
string K(const string k) { return g_prefix + k; }
double GV(const string k, const double def = 0.0)
  {
   return GlobalVariableCheck(K(k)) ? GlobalVariableGet(K(k)) : def;
  }
void   GS(const string k, const double v) { GlobalVariableSet(K(k), v); }
bool   GH(const string k) { return GlobalVariableCheck(K(k)); }
string CK(const int c, const string f) { return "c" + IntegerToString(c) + "_" + f; }
string TK(const ulong t, const string f) { return f + "_" + IntegerToString((long)t); }

//+------------------------------------------------------------------+
int OnInit()
  {
   g_prefix = "TPB_" + _Symbol + "_";
   trade.SetExpertMagicNumber(0);
   trade.SetDeviationInPoints(50);
   EventSetTimer(1);
   if(InpShowPanel)
     {
      CreateButton("TPB_new",   "CHU KY MOI", 10, 30);
      CreateButton("TPB_merge", "GOP LENH CUOI", 120, 30);
     }
   Process();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ObjectDelete(0, "TPB_new");
   ObjectDelete(0, "TPB_merge");
   Comment("");
  }

void OnTimer()
  {
   Process();
   if(InpWebUrl != "" && TimeCurrent() - g_lastPush >= InpPushSeconds)
     {
      PushWeb();
      g_lastPush = TimeCurrent();
     }
   if(TimeCurrent() - g_lastCleanup >= 60)
     {
      Cleanup();
      g_lastCleanup = TimeCurrent();
     }
  }

//+------------------------------------------------------------------+
//| Ghi nhan loi/lo khi lenh dong (TP, SL, dong tay, dong 1 phan)    |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
      return;

   ulong pid = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   if(!GH(TK(pid, "t")))
      return;

   int c = (int)GV(TK(pid, "t"));
   double pnl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
              + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
              + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   GS(CK(c, "pnl"), GV(CK(c, "pnl")) + pnl);
   if(pnl > 0)
      GS(CK(c, "win"), 1);   // chu ky da chot loi -> lenh 0.01 tiep theo la chu ky moi
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;
   if(sparam == "TPB_new")
     {
      GS("force_new", 1);
      Print("TPB: lenh tiep theo se mo CHU KY MOI");
     }
   if(sparam == "TPB_merge")
      MergeLast();
   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   Process();
  }

//+------------------------------------------------------------------+
bool IsTracked()
  {
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return false;
   if(PositionGetInteger(POSITION_MAGIC) != 0)
      return false;
   if(InpOnlyEmptyComment && PositionGetString(POSITION_COMMENT) != "")
      return false;
   return true;
  }

int Collect(Pos &a[])
  {
   ArrayResize(a, 0);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsTracked())
         continue;
      Pos p;
      p.ticket  = t;
      p.type    = (int)PositionGetInteger(POSITION_TYPE);
      p.timeMsc = PositionGetInteger(POSITION_TIME_MSC);
      p.vol     = PositionGetDouble(POSITION_VOLUME);
      p.price   = PositionGetDouble(POSITION_PRICE_OPEN);
      p.sl      = PositionGetDouble(POSITION_SL);
      p.tp      = PositionGetDouble(POSITION_TP);
      p.profit  = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      p.cycle   = GH(TK(t, "t")) ? (int)GV(TK(t, "t")) : -1;
      p.manual  = GV(TK(t, "man")) > 0;
      int n = ArraySize(a);
      ArrayResize(a, n + 1);
      a[n] = p;
     }
   // sap xep theo thoi gian vao lenh tang dan
   int n = ArraySize(a);
   for(int i = 0; i < n - 1; i++)
      for(int j = 0; j < n - 1 - i; j++)
         if(a[j].timeMsc > a[j + 1].timeMsc)
           {
            Pos tmp = a[j];
            a[j] = a[j + 1];
            a[j + 1] = tmp;
           }
   return n;
  }

//+------------------------------------------------------------------+
//| Gan lenh moi vao chu ky                                          |
//| Chu ky moi khi:                                                  |
//|  - chua co lenh nao cua chu ky hien tai dang mo, HOAC            |
//|  - lenh moi nguoc chieu chu ky hien tai, HOAC                    |
//|  - lenh moi = lot mo dau (0.01) VA chuoi hien tai dang DUONG,    |
//|    (chuoi dang am -> 0.01 la chia vol, van cung chuoi),          |
//|  - hoac anh bam nut CHU KY MOI                                   |
//| Chu ky cu khi da sang chu ky moi: EA khong sua SL/TP nua         |
//+------------------------------------------------------------------+
void AssignCycles(Pos &a[])
  {
   int n = ArraySize(a);
   int cur = (int)GV("cycle");
   for(int i = 0; i < n; i++)
     {
      if(a[i].cycle >= 0)
         continue;

      bool isNew = (cur == 0);
      if(!isNew)
        {
         int openCur = 0;
         double fl = 0;   // lai/lo tha noi cua chuoi hien tai (khong tinh lenh moi chua gan)
         for(int j = 0; j < n; j++)
            if(a[j].cycle == cur)
              {
               openCur++;
               fl += a[j].profit;
              }
         bool startLot = a[i].vol <= InpStartLot + 1e-8;
         // 0.01 moi: chuoi dang AM -> chia vol vao chuoi cu; chuoi dang DUONG -> chu ky moi
         isNew = (openCur == 0)
              || (a[i].type != (int)GV(CK(cur, "dir")))
              || (startLot && fl >= 0)
              || (GV("force_new") > 0);
        }

      if(isNew)
        {
         cur++;
         GS("cycle", cur);
         GS(CK(cur, "dir"), a[i].type);
         GS(CK(cur, "sl"), 0);
         GS(CK(cur, "win"), 0);
         GS(CK(cur, "pnl"), 0);
         GS("force_new", 0);
         PrintFormat("TPB: CHU KY MOI #%d bat dau tu lenh %I64u (%.2f lot)", cur, a[i].ticket, a[i].vol);
        }
      GS(TK(a[i].ticket, "t"), cur);
      a[i].cycle = cur;
     }
  }

//+------------------------------------------------------------------+
//| Dong bo SL + tinh TP cho chu ky hien tai                         |
//+------------------------------------------------------------------+
void Manage(Pos &a[])
  {
   int cur = (int)GV("cycle");
   s_cycle = cur;
   s_dir = -1; s_steps = 0; s_lots = 0; s_avg = 0; s_sl = 0; s_tp = 0;
   s_risk = 0; s_reward = 0; s_float = 0;
   if(cur == 0)
     {
      g_status = "Chua co chu ky";
      return;
     }

   int n = ArraySize(a);
   int dir = (int)GV(CK(cur, "dir"));
   s_dir = dir;
   double pt = _Point / 2.0;
   double csl = GV(CK(cur, "sl"));
   bool won = GV(CK(cur, "win")) > 0;

   // 1) SL chung: lenh moi nhat co SL khac SL chu ky = anh vua doi SL -> lay SL do
   for(int i = n - 1; i >= 0; i--)
      if(a[i].cycle == cur && a[i].sl > 0 && MathAbs(a[i].sl - csl) > pt)
        {
         csl = a[i].sl;
         GS(CK(cur, "sl"), csl);
         break;
        }
   s_sl = csl;

   // 2) Phat hien lenh anh da tu chinh TP
   double sv = 0, spv = 0;
   for(int i = 0; i < n; i++)
     {
      if(a[i].cycle != cur)
         continue;
      if(!a[i].manual && GH(TK(a[i].ticket, "tp")) && MathAbs(a[i].tp - GV(TK(a[i].ticket, "tp"))) > pt)
        {
         a[i].manual = true;
         GS(TK(a[i].ticket, "man"), 1);
         PrintFormat("TPB: lenh %I64u da duoc chinh TP tay -> EA bo qua TP lenh nay", a[i].ticket);
        }
      s_steps++;
      s_lots  += a[i].vol;
      s_float += a[i].profit;
      if(!a[i].manual)
        {
         sv  += a[i].vol;
         spv += a[i].vol * a[i].price;
        }
     }
   if(s_steps == 0)
     {
      g_status = "Chu ky #" + IntegerToString(cur) + " da dong het";
      return;
     }

   if(csl <= 0)
     {
      g_status = "CHUA CO SL - hay dat SL cho 1 lenh";
      return;
     }

   // 3) Tinh TP: TB gia (theo vol) cua cac lenh EA quan ly
   double ntp = 0;
   if(sv > 0)
     {
      double avg = spv / sv;
      s_avg = avg;
      bool slOk = (dir == POSITION_TYPE_SELL) ? (csl > avg) : (csl < avg);
      if(!slOk)
        {
         g_status = "SL nam sai phia gia trung binh";
         return;
        }
      double dist = MathAbs(csl - avg) * InpRR;
      ntp = NormalizeDouble(dir == POSITION_TYPE_SELL ? avg - dist : avg + dist, _Digits);
      s_tp = ntp;
     }

   // 4) Ap SL/TP (chu ky da chot loi -> dong bang, khong doi gi nua)
   g_status = won ? "Da chot loi - chu ky dong bang" : "Dang quan ly";
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   for(int i = 0; i < n; i++)
     {
      if(a[i].cycle != cur)
         continue;

      // tien rui ro / loi muc tieu theo $
      double r = 0, w = 0;
      ENUM_ORDER_TYPE ot = (dir == POSITION_TYPE_SELL) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      if(OrderCalcProfit(ot, _Symbol, a[i].vol, a[i].price, csl, r))
         s_risk += r;
      double tgt = a[i].manual ? a[i].tp : ntp;
      if(tgt > 0 && OrderCalcProfit(ot, _Symbol, a[i].vol, a[i].price, tgt, w))
         s_reward += w;

      if(won)
         continue;

      double wantTp = a[i].manual ? a[i].tp : ntp;
      if(!a[i].manual)
        {
         bool tpOk = (dir == POSITION_TYPE_SELL) ? (wantTp < ask - stopDist) : (wantTp > bid + stopDist);
         if(!tpOk)
            wantTp = a[i].tp; // gia da vuot TP -> khong dat duoc, giu nguyen
        }
      if(MathAbs(a[i].sl - csl) > pt || MathAbs(a[i].tp - wantTp) > pt)
        {
         if(trade.PositionModify(a[i].ticket, csl, wantTp))
           {
            if(!a[i].manual)
               GS(TK(a[i].ticket, "tp"), wantTp);
           }
         else
            PrintFormat("TPB: loi sua lenh %I64u: %d %s", a[i].ticket,
                        trade.ResultRetcode(), trade.ResultRetcodeDescription());
        }
      else if(!a[i].manual && !GH(TK(a[i].ticket, "tp")))
         GS(TK(a[i].ticket, "tp"), a[i].tp);
     }
  }

void Process()
  {
   Pos a[];
   Collect(a);
   AssignCycles(a);
   Manage(a);
   if(InpShowPanel)
      DrawPanel();
  }

//+------------------------------------------------------------------+
//| Nut GOP LENH CUOI: dua lenh moi nhat ve chu ky truoc             |
//+------------------------------------------------------------------+
void MergeLast()
  {
   Pos a[];
   int n = Collect(a);
   int cur = (int)GV("cycle");
   if(n == 0 || cur <= 1)
      return;
   Pos last = a[n - 1];
   if(last.cycle != cur)
      return;
   GS(TK(last.ticket, "t"), cur - 1);
   int others = 0;
   for(int i = 0; i < n - 1; i++)
      if(a[i].cycle == cur)
         others++;
   if(others == 0)
      GS("cycle", cur - 1);
   PrintFormat("TPB: gop lenh %I64u ve chu ky #%d", last.ticket, cur - 1);
  }

//+------------------------------------------------------------------+
//| Xoa global variable cua lenh da dong                             |
//+------------------------------------------------------------------+
void Cleanup()
  {
   for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
     {
      string name = GlobalVariableName(i);
      if(StringFind(name, g_prefix) != 0)
         continue;
      string rest = StringSubstr(name, StringLen(g_prefix));
      int us = StringFind(rest, "_");
      if(us < 0)
         continue;
      string f = StringSubstr(rest, 0, us);
      if(f != "t" && f != "tp" && f != "man")
         continue;
      ulong t = (ulong)StringToInteger(StringSubstr(rest, us + 1));
      if(!PositionSelectByTicket(t))
         GlobalVariableDel(name);
     }
  }

//+------------------------------------------------------------------+
//| Panel                                                            |
//+------------------------------------------------------------------+
void CreateButton(const string name, const string text, const int x, const int y)
  {
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, 105);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, 22);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
  }

string DirText(const int d)
  {
   return d == POSITION_TYPE_SELL ? "SELL" : (d == POSITION_TYPE_BUY ? "BUY" : "-");
  }

void DrawPanel()
  {
   string s = "=== TP BALANCER (RR " + DoubleToString(InpRR, 2) + ") ===\n";
   s += "Chu ky: #" + IntegerToString(s_cycle) + "  " + DirText(s_dir) + "   Bac: " + IntegerToString(s_steps) + "\n";
   s += "Tong lot: " + DoubleToString(s_lots, 2) + "   Gia TB: " + DoubleToString(s_avg, _Digits) + "\n";
   s += "SL: " + DoubleToString(s_sl, _Digits) + "   TP: " + DoubleToString(s_tp, _Digits) + "\n";
   s += "Rui ro: " + DoubleToString(s_risk, 2) + " $   Muc tieu: " + DoubleToString(s_reward, 2) + " $\n";
   s += "Tha noi: " + DoubleToString(s_float, 2) + " $\n";
   s += "Trang thai: " + g_status + (GV("force_new") > 0 ? "  [LENH TIEP = CHU KY MOI]" : "");
   Comment(s);
  }

//+------------------------------------------------------------------+
//| Gui du lieu len web                                              |
//+------------------------------------------------------------------+
string J(const string k, const string v, const bool q = false)
  {
   return "\"" + k + "\":" + (q ? "\"" + v + "\"" : v);
  }
string D(const double v, const int d = 2) { return DoubleToString(v, d); }

void PushWeb()
  {
   Pos a[];
   int n = Collect(a);
   string pos = "";
   for(int i = 0; i < n; i++)
     {
      if(pos != "")
         pos += ",";
      pos += "{" + J("ticket", IntegerToString((long)a[i].ticket)) + ","
           + J("cycle", IntegerToString(a[i].cycle)) + ","
           + J("type", DirText(a[i].type), true) + ","
           + J("vol", D(a[i].vol)) + ","
           + J("price", D(a[i].price, _Digits)) + ","
           + J("sl", D(a[i].sl, _Digits)) + ","
           + J("tp", D(a[i].tp, _Digits)) + ","
           + J("profit", D(a[i].profit)) + ","
           + J("manual", a[i].manual ? "true" : "false") + "}";
     }

   string hist = "";
   for(int c = s_cycle; c >= 1 && c > s_cycle - 20; c--)
     {
      if(hist != "")
         hist += ",";
      hist += "{" + J("cycle", IntegerToString(c)) + ","
            + J("dir", DirText((int)GV(CK(c, "dir"), -1)), true) + ","
            + J("pnl", D(GV(CK(c, "pnl")))) + ","
            + J("win", GV(CK(c, "win")) > 0 ? "true" : "false") + "}";
     }

   string json = "{"
      + J("key", InpWebKey, true) + ","
      + J("account", IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))) + ","
      + J("symbol", _Symbol, true) + ","
      + J("serverTime", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), true) + ","
      + J("balance", D(AccountInfoDouble(ACCOUNT_BALANCE))) + ","
      + J("equity", D(AccountInfoDouble(ACCOUNT_EQUITY))) + ","
      + J("bid", D(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits)) + ","
      + J("rr", D(InpRR)) + ","
      + J("cycle", IntegerToString(s_cycle)) + ","
      + J("dir", DirText(s_dir), true) + ","
      + J("steps", IntegerToString(s_steps)) + ","
      + J("lots", D(s_lots)) + ","
      + J("avg", D(s_avg, _Digits)) + ","
      + J("sl", D(s_sl, _Digits)) + ","
      + J("tp", D(s_tp, _Digits)) + ","
      + J("risk", D(s_risk)) + ","
      + J("reward", D(s_reward)) + ","
      + J("floating", D(s_float)) + ","
      + J("status", g_status, true) + ","
      + "\"positions\":[" + pos + "],"
      + "\"history\":[" + hist + "]}";

   char data[], res[];
   string resHeaders;
   StringToCharArray(json, data, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(data, ArraySize(data) - 1); // bo ky tu ket thuc chuoi
   ResetLastError();
   int code = WebRequest("POST", InpWebUrl, "Content-Type: application/json\r\n", 5000, data, res, resHeaders);
   if(code == -1)
      PrintFormat("TPB: WebRequest loi %d - nho them URL vao Tools > Options > Expert Advisors", GetLastError());
  }
//+------------------------------------------------------------------+
