#property strict
#property version "1.00"
#property description "Previous completed session value-area reversion research EA. STRATEGY TESTER ONLY."
#include "Include/BVTypes.mqh"
#include "Include/BVTime.mqh"
#include "Include/BVProfile.mqh"
#include "Include/BVSignal.mqh"
#include "Include/BVJournal.mqh"
#include "Include/BVExecution.mqh"

input group "Research identity (new RunId for every independent test)"
input string InpRunId="research_001";
input string InpConfigLabel="UNVALIDATED_baseline";
input ulong InpMagic=26002501;
input group "Historical clock (must configure from broker records)"
input BVSessionMode InpSessionMode=BV_NEW_YORK_SESSION;
input BVBrokerRule InpBrokerOffsetRule=BV_OFFSET_UNCONFIGURED;
input int InpBrokerWinterUTCMinutes=120;
input int InpBrokerSummerUTCMinutes=180;
input int InpCustomBoundaryMinutes=1080;
input group "Frozen previous session profile"
input BVVolumeMode InpVolumeMode=BV_AUTO;
input int InpProfileRows=100;
input double InpValueAreaPercent=70.0;
input int InpMinProfileM1Bars=1000;
input double InpMinProfileCoveragePercent=90.0;
input int InpMaxProfileGapMinutes=90;
input int InpMaxProfileEdgeGapMinutes=180;
input group "Signals and New York entry window"
input ENUM_TIMEFRAMES InpSignalTimeframe=PERIOD_M15;
input int InpMaxReclaimBars=5;
input bool InpRequireEngulfing=true;
input int InpEntryStartNYMinutes=585;
input int InpEntryEndNYMinutes=690;
input int InpMaxEntryDelaySeconds=60;
input group "Stops, costs and risk"
input int InpATRPeriod=14;
input double InpBufferTicks=2.0;
input double InpATRBufferFraction=0.10;
input double InpMinRewardRisk=1.5;
input double InpRiskPercent=0.25;
input double InpDailyLossPercent=0.75;
input double InpInitialDayEquity=0.0;
input double InpCommissionRoundTurnPerLot=0.0;
input double InpSlippageTicksPerSide=0.0;
input double InpMaxSpreadPoints=0.0; // REQUIRED broker-specific POINTS, not ticks
input uint InpOrderDeviationPoints=20;
input bool InpForceExit=true;
input int InpForceExitNYMinutes=955;
input group "Optional local UTC blackouts and visual output"
input bool InpUseBlackouts=false;
input string InpBlackoutFile="Biltech_blackouts.csv";
input bool InpShowVisuals=true;

struct BVBlackout { datetime start,end; string label; };
struct BVPositionStats
  {
   ulong id;
   int direction;
   datetime entry_time,exit_time;
   double in_volume,out_volume,entry_value,exit_value,gross,commission,swap,fees,risk,sl,tp;
   string reason;
   bool mixed;
  };
BVClock g_clock;
BVProfile g_profile;
BVSession g_session;
BVSetup g_long,g_short;
BVSymbolSpec g_spec;
BVJournal g_journal;
BVBlackout g_blackouts[];
BVPositionStats g_positions[];
BVKeySet g_signal_ids,g_trade_ids;
int g_signals=INVALID_HANDLE,g_trades=INVALID_HANDLE,g_atr=INVALID_HANDLE;
int g_tf=0;
datetime g_cursor=0,g_last_seen_closed=0,g_day_start_utc=0;
string g_config="",g_prefix="",g_day="",g_fatal="";
double g_day_equity=0,g_realized=0,g_floating=0;
bool g_locked=true,g_history_dirty=true,g_initialized=false,g_replay=false;
bool g_ownership_complete=false;
int g_history_count=-1;
int g_audit_records=0;

string U64(const ulong value) { return StringFormat("%I64u",value); }
string SafeName(const string value)
  {
   string result="";
   for(int i=0;i<StringLen(value);i++)
     { ushort c=StringGetCharacter(value,i); if((c>=48 && c<=57)||(c>=65 && c<=90)||(c>=97 && c<=122)||c==95||c==45) result+=ShortToString(c); else result+="_"; }
   return result;
  }
string ConfigText(void)
  {
   return StringFormat("v1|%s|%I64u|%d|%d|%d|%d|%d|%d|%d|%.8f|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%.8f|%.8f|%.8f|%.8f|%.8f|%.8f|%.8f|%.8f|%.8f|%u|%d|%d|%d|%s",
    _Symbol,InpMagic,(int)InpSessionMode,(int)InpBrokerOffsetRule,InpBrokerWinterUTCMinutes,InpBrokerSummerUTCMinutes,InpCustomBoundaryMinutes,
    (int)InpVolumeMode,InpProfileRows,InpValueAreaPercent,InpMinProfileM1Bars,InpMaxProfileGapMinutes,InpMaxProfileEdgeGapMinutes,
    (int)InpSignalTimeframe,InpMaxReclaimBars,(int)InpRequireEngulfing,InpEntryStartNYMinutes,InpEntryEndNYMinutes,InpMaxEntryDelaySeconds,InpATRPeriod,
    InpBufferTicks,InpATRBufferFraction,InpMinRewardRisk,InpRiskPercent,InpDailyLossPercent,InpInitialDayEquity,
    InpCommissionRoundTurnPerLot,InpSlippageTicksPerSide,InpMaxSpreadPoints,InpOrderDeviationPoints,(int)InpForceExit,InpForceExitNYMinutes,(int)InpUseBlackouts,InpBlackoutFile)+"|coverage="+BVNum(InpMinProfileCoveragePercent)+"|run="+InpRunId+"|account="+U64((ulong)AccountInfoInteger(ACCOUNT_LOGIN))+"|currency="+AccountInfoString(ACCOUNT_CURRENCY)+"|margin_mode="+IntegerToString(AccountInfoInteger(ACCOUNT_MARGIN_MODE));
  }
uint Hash(const string text)
  { uint h=2166136261; for(int i=0;i<StringLen(text);i++) { h^=(uint)StringGetCharacter(text,i); h*=16777619; } return h; }
bool Durable(const string kind,const string key,const string a="",const string b="",const string c="")
  {
   if(g_journal.Put(kind,key,a,b,c)) return true;
   g_fatal="journal_write_failed: new entries disabled"; Print(g_fatal); return false;
  }
bool WriteLine(const int h,const string line)
  {
   if(h==INVALID_HANDLE || FileWriteString(h,line+"\r\n")==0) { g_fatal="csv_write_failed"; Print(g_fatal); return false; }
   FileFlush(h); return true;
  }
bool HasAudit(const bool signal,const string id)
  {
   return signal?g_signal_ids.Has(id):g_trade_ids.Has(id);
  }
void RememberAudit(const bool signal,const string id)
  {
   if(signal) g_signal_ids.Add(id); else g_trade_ids.Add(id);
   g_audit_records++;
  }
bool AuditWrite(const bool signal,const string id,const string line)
  {
   if(HasAudit(signal,id)) return true;
   string kind=signal?"OUTBOX_SIGNAL":"OUTBOX_TRADE";
   if(!g_journal.Has(kind,id) && !Durable(kind,id,line)) return false;
   if(!WriteLine(signal?g_signals:g_trades,line)) return false;
   RememberAudit(signal,id); return true;
  }
bool LoadAudit(const bool signal,string &reason)
  {
   int h=signal?g_signals:g_trades; FileSeek(h,0,SEEK_SET);
   string header=FileReadString(h); int expected=signal?43:27;
   while(!FileIsEnding(h))
     {
      string line=FileReadString(h),id=""; if(line=="" && FileIsEnding(h)) break;
      if(!BVParseCSVRow(line,expected,id) || HasAudit(signal,id))
        { reason="Malformed, partial or duplicate audit CSV row. Preserve files and repair from journal outbox before continuation."; return false; }
      RememberAudit(signal,id);
     }
   FileSeek(h,0,SEEK_END); return true;
  }
bool RecoverAudit(void)
  {
   int count=g_journal.Count(); BVJournalRow r;
   for(int i=0;i<count;i++)
     {
      if(!g_journal.Row(i,r)) return false;
      if(r.kind=="OUTBOX_SIGNAL" && !AuditWrite(true,r.key,r.a)) return false;
      if(r.kind=="OUTBOX_TRADE" && !AuditWrite(false,r.key,r.a)) return false;
     }
   return true;
  }
bool ValidateHistoryContinuation(string &reason)
  {
   if(!HistorySelect(0,TimeCurrent())) { reason="Cannot load history for restart validation"; return false; }
   BVJournalRow row;
   for(int i=0;i<g_journal.Count();i++)
     {
      if(!g_journal.Row(i,row)) return false;
      if(row.kind!="RISK") continue;
      ulong deal=(ulong)StringToInteger(row.key);
      if(HistoryDealGetInteger(deal,DEAL_TIME)<=0 || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol || (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=InpMagic)
        { reason="Persisted entry deal absent from current account history. Restore matching run/history or select a NEW RunId for an independent test."; return false; }
     }
   return true;
  }
void LogSignal(const string event,const string status,const string reason,const datetime broker,
                const BVSignal &signal,const BVPlan &plan,const string extra="")
  {
   if(g_signals==INVALID_HANDLE || g_replay) return;
   string id=event+"|"+g_session.id+"|"+IntegerToString(signal.direction)+"|"+IntegerToString((long)broker)+"|"+reason;
   if(HasAudit(true,id)) return;
   datetime utc=0; string error=""; g_clock.BrokerToUTC(broker,utc,error);
   string row="";
   BVCSVAdd(row,id); BVCSVAdd(row,event); BVCSVAdd(row,status); BVCSVAdd(row,reason); BVCSVAdd(row,_Symbol);
   BVCSVAdd(row,g_config); BVCSVAdd(row,InpRunId); BVCSVAdd(row,BVStamp(broker)); BVCSVAdd(row,BVStamp(utc)); BVCSVAdd(row,BVStamp(g_clock.UTCToNY(utc)));
   BVCSVAdd(row,g_session.id); BVCSVAdd(row,g_profile.session.id); BVCSVAdd(row,BVStamp(g_profile.session.start_broker)); BVCSVAdd(row,BVStamp(g_profile.session.end_broker));
   BVCSVAdd(row,BVStamp(g_profile.session.start_utc)); BVCSVAdd(row,BVStamp(g_profile.session.end_utc)); BVCSVAdd(row,BVSourceName(g_profile.source)); BVCSVAdd(row,g_profile.source_note);
   BVCSVAdd(row,BVNum(g_profile.val)); BVCSVAdd(row,BVNum(g_profile.vah)); BVCSVAdd(row,BVNum(g_profile.poc)); BVCSVAdd(row,IntegerToString(signal.direction));
   BVCSVAdd(row,BVStamp(signal.breakout_time)); BVCSVAdd(row,BVStamp(signal.reclaim_time)); BVCSVAdd(row,BVNum(signal.breakout_volume)); BVCSVAdd(row,BVNum(signal.reclaim_volume));
   BVCSVAdd(row,IntegerToString(signal.bars)); BVCSVAdd(row,IntegerToString(signal.weakening)); BVCSVAdd(row,IntegerToString(signal.engulfing)); BVCSVAdd(row,BVNum(signal.extreme));
   BVCSVAdd(row,BVNum(signal.atr)); BVCSVAdd(row,BVNum(signal.buffer)); BVCSVAdd(row,BVStamp(signal.entry_due));
   BVCSVAdd(row,BVNum(plan.entry)); BVCSVAdd(row,BVNum(plan.actual_entry)); BVCSVAdd(row,BVNum(plan.sl)); BVCSVAdd(row,BVNum(plan.tp)); BVCSVAdd(row,BVNum(plan.spread_points));
   BVCSVAdd(row,BVNum(plan.rr)); BVCSVAdd(row,BVNum(plan.risk_budget)); BVCSVAdd(row,BVNum(plan.volume)); BVCSVAdd(row,BVNum(plan.initial_risk)); BVCSVAdd(row,extra);
   AuditWrite(true,id,row);
  }
void LogSimple(const string event,const string status,const string reason,const datetime broker,const string extra="")
  { BVSignal s; BVPlan p; ZeroMemory(s); ZeroMemory(p); LogSignal(event,status,reason,broker,s,p,extra); }

bool ParseUTC(const string text,datetime &value)
  {
   if(StringLen(text)!=19) return false;
   value=StringToTime(text);
   return value>0 && TimeToString(value,TIME_DATE|TIME_SECONDS)==text;
  }
bool LoadBlackouts(string &reason)
  {
   if(!InpUseBlackouts) return true;
   int h=FileOpen(InpBlackoutFile,FILE_READ|FILE_CSV|FILE_ANSI,',',CP_UTF8);
   if(h==INVALID_HANDLE) { reason="Blackout file requested but missing in tester MQL5/Files: "+InpBlackoutFile; return false; }
   string a=FileReadString(h),b=FileReadString(h),c=FileReadString(h);
   if(a!="start_utc" || b!="end_utc" || c!="label" || !FileIsLineEnding(h))
     { FileClose(h); reason="Blackout CSV header must be start_utc,end_utc,label (UTF-8 without BOM)"; return false; }
   while(!FileIsEnding(h))
     {
      a=FileReadString(h); if(a=="" && FileIsEnding(h)) break;
      b=FileReadString(h); c=FileReadString(h); BVBlackout x;
      if(!ParseUTC(a,x.start)||!ParseUTC(b,x.end)||x.end<=x.start||c==""||!FileIsLineEnding(h))
        { FileClose(h); reason="Invalid blackout interval; expected UTC YYYY.MM.DD HH:MM:SS, end>start and label"; return false; }
      x.label=c; int n=ArraySize(g_blackouts); ArrayResize(g_blackouts,n+1); g_blackouts[n]=x;
     }
   FileClose(h); return true;
  }
bool IsBlackout(const datetime utc,string &label)
  { for(int i=0;i<ArraySize(g_blackouts);i++) if(utc>=g_blackouts[i].start && utc<g_blackouts[i].end) { label=g_blackouts[i].label; return true; } return false; }

int PositionIndex(const ulong id)
  {
   for(int i=0;i<ArraySize(g_positions);i++) if(g_positions[i].id==id) return i;
   int n=ArraySize(g_positions); ArrayResize(g_positions,n+1); ZeroMemory(g_positions[n]); g_positions[n].id=id; return n;
  }
bool PositionOpen(const ulong id)
  { for(int i=PositionsTotal()-1;i>=0;i--) { ulong t=PositionGetTicket(i); if(t>0 && (ulong)PositionGetInteger(POSITION_IDENTIFIER)==id) return true; } return false; }
bool OwnedPosition(const ulong ticket)
  {
   if(!g_ownership_complete || g_history_dirty) return false;
   if(!PositionSelectByTicket(ticket) || PositionGetString(POSITION_SYMBOL)!=_Symbol || (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) return false;
   ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
   for(int i=0;i<ArraySize(g_positions);i++) if(g_positions[i].id==id) return !g_positions[i].mixed;
   return false; // no ownership proof -> never close
  }
string DealReason(const ulong deal)
  {
   ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID); BVJournalRow r;
   ENUM_DEAL_REASON why=(ENUM_DEAL_REASON)HistoryDealGetInteger(deal,DEAL_REASON);
   if(why==DEAL_REASON_SL) return "STOP_LOSS";
   if(why==DEAL_REASON_TP) return "TAKE_PROFIT";
   if(why==DEAL_REASON_SO) return "STOP_OUT";
   if(g_journal.Find("EXIT",U64(id),r)) return r.a;
   return EnumToString(why);
  }
void TradeRow(const string event,const string event_id,const ulong deal,const BVPositionStats &p)
  {
   string row="",error=""; datetime utc=0,entry_utc=0,exit_utc=0;
   datetime time=event=="DEAL" ? (datetime)HistoryDealGetInteger(deal,DEAL_TIME) : p.exit_time;
   g_clock.BrokerToUTC(time,utc,error); g_clock.BrokerToUTC(p.entry_time,entry_utc,error);
   if(p.exit_time>0) g_clock.BrokerToUTC(p.exit_time,exit_utc,error);
   double gross=p.gross,commission=p.commission,swap=p.swap,fees=p.fees,volume=p.in_volume,price=p.in_volume>0?p.entry_value/p.in_volume:0;
   if(event=="DEAL") { gross=HistoryDealGetDouble(deal,DEAL_PROFIT); commission=HistoryDealGetDouble(deal,DEAL_COMMISSION); swap=HistoryDealGetDouble(deal,DEAL_SWAP); fees=HistoryDealGetDouble(deal,DEAL_FEE); volume=HistoryDealGetDouble(deal,DEAL_VOLUME); price=HistoryDealGetDouble(deal,DEAL_PRICE); }
   double net=gross+commission+swap+fees;
   BVCSVAdd(row,event_id); BVCSVAdd(row,event); BVCSVAdd(row,U64(p.id)); BVCSVAdd(row,U64(deal)); BVCSVAdd(row,_Symbol); BVCSVAdd(row,g_config);
   BVCSVAdd(row,p.direction>0?"LONG":"SHORT"); BVCSVAdd(row,BVStamp(time)); BVCSVAdd(row,BVStamp(utc)); BVCSVAdd(row,BVStamp(g_clock.UTCToNY(utc)));
   BVCSVAdd(row,BVStamp(entry_utc)); BVCSVAdd(row,BVStamp(exit_utc)); BVCSVAdd(row,BVStamp(g_clock.UTCToNY(exit_utc)));
   BVCSVAdd(row,BVNum(price)); BVCSVAdd(row,BVNum(volume)); BVCSVAdd(row,BVNum(p.sl)); BVCSVAdd(row,BVNum(p.tp));
   BVCSVAdd(row,BVNum(gross)); BVCSVAdd(row,BVNum(commission)); BVCSVAdd(row,BVNum(swap)); BVCSVAdd(row,BVNum(fees)); BVCSVAdd(row,BVNum(net));
   BVCSVAdd(row,BVNum(p.risk)); BVCSVAdd(row,p.risk>0?BVNum(net/p.risk):""); BVCSVAdd(row,IntegerToString(exit_utc>0 && entry_utc>0?(long)(exit_utc-entry_utc):0));
   BVCSVAdd(row,event=="DEAL"?DealReason(deal):p.reason); BVCSVAdd(row,p.mixed?"OWNERSHIP_CONFLICT":"");
   AuditWrite(false,event_id,row);
  }
bool SyncHistory(void)
  {
   if(!HistorySelect(0,TimeCurrent())) { g_ownership_complete=false; g_fatal="history_select_failed"; return false; }
   int total=HistoryDealsTotal();
   if(!g_history_dirty && total==g_history_count) return true;
   g_ownership_complete=false; ArrayResize(g_positions,0); g_realized=0;
   // First discover EA entry ownership; then account every deal for those IDs,
   // including manually closed exits and all attached commissions/fees/swaps.
   for(int i=0;i<total;i++)
     {
      ulong d=HistoryDealGetTicket(i);
      if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol || (ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=InpMagic) continue;
      ENUM_DEAL_ENTRY e=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(d,DEAL_ENTRY);
      ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(d,DEAL_TYPE);
      if((type==DEAL_TYPE_BUY || type==DEAL_TYPE_SELL) && (e==DEAL_ENTRY_IN || e==DEAL_ENTRY_INOUT)) PositionIndex((ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID));
     }
   for(int i=0;i<total;i++)
     {
      ulong d=HistoryDealGetTicket(i),id=(ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID);
      int k=-1; for(int j=0;j<ArraySize(g_positions);j++) if(g_positions[j].id==id) { k=j; break; }
      if(k<0) continue;
      ENUM_DEAL_ENTRY e=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(d,DEAL_ENTRY);
      ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(d,DEAL_TYPE);
      bool market=type==DEAL_TYPE_BUY || type==DEAL_TYPE_SELL;
      datetime time=(datetime)HistoryDealGetInteger(d,DEAL_TIME),utc=0; string error="";
      double volume=HistoryDealGetDouble(d,DEAL_VOLUME),price=HistoryDealGetDouble(d,DEAL_PRICE);
      double gross=HistoryDealGetDouble(d,DEAL_PROFIT),commission=HistoryDealGetDouble(d,DEAL_COMMISSION),swap=HistoryDealGetDouble(d,DEAL_SWAP),fees=HistoryDealGetDouble(d,DEAL_FEE);
      g_positions[k].gross+=gross; g_positions[k].commission+=commission; g_positions[k].swap+=swap; g_positions[k].fees+=fees;
      if(!g_clock.BrokerToUTC(time,utc,error)) { g_fatal="deal_time_mapping_failed: "+error; return false; }
      if(utc>=g_day_start_utc) g_realized+=gross+commission+swap+fees;
      if(market && (ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=InpMagic) g_positions[k].mixed=true;
      if(market && e==DEAL_ENTRY_IN)
        {
         if(g_positions[k].entry_time==0) { g_positions[k].entry_time=time; g_positions[k].direction=type==DEAL_TYPE_BUY?1:-1; g_positions[k].sl=HistoryDealGetDouble(d,DEAL_SL); g_positions[k].tp=HistoryDealGetDouble(d,DEAL_TP); }
         g_positions[k].in_volume+=volume; g_positions[k].entry_value+=volume*price;
         double risk=0,cost=0; BVJournalRow r;
         if(g_journal.Find("RISK",U64(d),r)) risk=StringToDouble(r.a);
         else
           {
            double loss=0;
            if(time==TimeCurrent() && g_positions[k].sl>0 && OrderCalcProfit(type==DEAL_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,volume,price,g_positions[k].sl,loss) &&
               BVCostPerLot(g_positions[k].direction,price,g_spec,InpCommissionRoundTurnPerLot,InpSlippageTicksPerSide,cost)) risk=MathMax(0,-loss)+volume*cost;
            // No fabricated R when broker history lacks the original SL.
            if(!Durable("RISK",U64(d),BVNum(risk))) return false;
           }
         g_positions[k].risk+=risk;
        }
      else if(market && (e==DEAL_ENTRY_OUT || e==DEAL_ENTRY_OUT_BY))
        { g_positions[k].out_volume+=volume; g_positions[k].exit_value+=volume*price; g_positions[k].exit_time=time; g_positions[k].reason=DealReason(d); }
      else if(market && e==DEAL_ENTRY_INOUT) { g_positions[k].mixed=true; g_positions[k].reason="UNSUPPORTED_REVERSAL_OWNERSHIP_CONFLICT"; }
      if(!HasAudit(false,"deal_"+U64(d))) TradeRow("DEAL","deal_"+U64(d),d,g_positions[k]);
     }
   for(int k=0;k<ArraySize(g_positions);k++)
     {
      BVPositionStats p=g_positions[k];
      if(p.in_volume>0 && p.out_volume>=p.in_volume-g_spec.step*0.01 && !PositionOpen(p.id) && !HasAudit(false,"closed_"+U64(p.id)))
         TradeRow("CLOSED","closed_"+U64(p.id),0,p);
     }
   g_history_count=total; g_history_dirty=false; g_ownership_complete=true;
   return true;
  }

bool NewDay(const datetime utc)
  {
   string day="",reason=""; datetime start=0;
   if(!g_clock.NYDay(utc,day,start,reason)) { g_fatal=reason; return false; }
   if(day==g_day) return true;
   bool cold=g_day==""; g_day=day; g_day_start_utc=start; g_history_dirty=true;
   BVJournalRow r;
   if(g_journal.Find("DAY",day,r)) { g_day_equity=StringToDouble(r.a); g_locked=r.b=="1"; }
   else
     {
      g_day_equity=AccountInfoDouble(ACCOUNT_EQUITY);
      g_locked=cold && utc-start>InpMaxEntryDelaySeconds;
      if(cold && InpInitialDayEquity>0) { g_day_equity=InpInitialDayEquity; g_locked=false; }
      // History cannot reconstruct past floating breaches or an exact equity
      // baseline. Missing restart evidence must never reset the daily latch.
      bool activity=false;
      if(!HistorySelect(0,TimeCurrent())) { g_fatal="daily_history_recovery_failed"; return false; }
      for(int i=0;i<HistoryDealsTotal();i++)
        {
         ulong d=HistoryDealGetTicket(i); datetime deal_utc=0;
         if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol || (ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=InpMagic) continue;
         if(!g_clock.BrokerToUTC((datetime)HistoryDealGetInteger(d,DEAL_TIME),deal_utc,reason)) { g_fatal=reason; return false; }
         if(deal_utc>=start) activity=true;
        }
      if(activity && cold) g_locked=true;
      if(!Durable("DAY",day,BVNum(g_day_equity),g_locked?"1":"0")) return false;
      LogSimple("DAY",g_locked?"LOCKED":"ACTIVE",g_locked?"initial_partial_NY_day_no_equity_baseline":"daily_equity_recorded",TimeCurrent(),BVNum(g_day_equity));
     }
   return true;
  }
void CloseOwned(const string reason)
  {
   if(!MQLInfoInteger(MQL_TESTER)) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i); if(ticket==0 || !OwnedPosition(ticket)) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      datetime now=TimeCurrent();
      BVJournalRow previous;
      // One close attempt per position per broker second; rejected/partial closes
      // are retried on a later tradable tick. Position ownership is re-proved.
      if(g_journal.Find("CLOSE_TRY",U64(id),previous) && previous.time==now) continue;
      if(!Durable("EXIT",U64(id),reason)||!Durable("CLOSE_TRY",U64(id),reason)) return;
      ENUM_POSITION_TYPE side=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double volume=PositionGetDouble(POSITION_VOLUME); MqlTick tick;
      if(!SymbolInfoTick(_Symbol,tick)) continue;
      MqlTradeRequest request={}; MqlTradeResult result={}; string error="";
      request.action=TRADE_ACTION_DEAL; request.position=ticket; request.symbol=_Symbol; request.magic=InpMagic;
      request.volume=volume; request.type=side==POSITION_TYPE_BUY?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
      request.price=side==POSITION_TYPE_BUY?tick.bid:tick.ask; request.deviation=InpOrderDeviationPoints; request.comment=reason;
      if(!BVFillMode(g_spec,request.type_filling,error)) continue;
      bool sent=OrderSend(request,result); g_history_dirty=true;
      bool accepted=sent && (result.retcode==TRADE_RETCODE_DONE || result.retcode==TRADE_RETCODE_DONE_PARTIAL || result.retcode==TRADE_RETCODE_PLACED);
      LogSimple("EXIT_REQUEST",accepted?"SUBMITTED":"REJECTED",reason,now,StringFormat("position=%I64u retcode=%u %s",id,result.retcode,result.comment));
     }
  }
void ManageRisk(const datetime utc)
  {
   g_floating=0;
   for(int i=0;i<ArraySize(g_positions);i++)
      if(g_fatal=="" && g_positions[i].mixed && PositionOpen(g_positions[i].id))
        { g_fatal="mixed_position_ownership_conflict"; LogSimple("OWNERSHIP","LOCKED",g_fatal,TimeCurrent(),U64(g_positions[i].id)); }
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i); if(ticket==0 || !OwnedPosition(ticket) || !PositionSelectByTicket(ticket)) continue;
      g_floating+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      if(g_fatal=="" && (PositionGetDouble(POSITION_SL)<=0 || PositionGetDouble(POSITION_TP)<=0))
        { g_fatal="owned_position_missing_protective_SL_or_TP"; LogSimple("PROTECTION","LOCKED",g_fatal,TimeCurrent()); }
     }
   if(!g_locked && (g_day_equity<=0 || g_realized+g_floating<=-g_day_equity*InpDailyLossPercent/100.0))
     { g_locked=true; Durable("DAY",g_day,BVNum(g_day_equity),"1"); LogSimple("DAILY_LOCK","LOCKED","daily_realized_plus_floating_loss",TimeCurrent(),BVNum(g_realized+g_floating)); }
   if(g_locked) CloseOwned("DAILY_LOCKOUT");
   if(g_fatal!="") CloseOwned("DATA_OR_AUDIT_FAILURE");
   if(!InpForceExit) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i); if(ticket==0 || !OwnedPosition(ticket) || !PositionSelectByTicket(ticket)) continue;
      datetime opened=(datetime)PositionGetInteger(POSITION_TIME),open_utc=0; string error="";
      if(!g_clock.BrokerToUTC(opened,open_utc,error)) continue;
      string open_day="",current_day=""; datetime a=0,b=0;
      if(!g_clock.NYDay(open_utc,open_day,a,error)||!g_clock.NYDay(utc,current_day,b,error)) continue;
      if(current_day>open_day || g_clock.AtOrAfterNY(utc,InpForceExitNYMinutes)) { CloseOwned("TIME_EXIT"); break; }
     }
  }
bool PositionRestriction(string &reason)
  {
   ENUM_ACCOUNT_MARGIN_MODE mode=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(mode!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) { reason="netting_symbol_position_or_ownership_conflict"; return false; }
      if((ulong)PositionGetInteger(POSITION_MAGIC)==InpMagic) { reason="one_EA_position_per_symbol"; return false; }
     }
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      if(OrderGetTicket(i)==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if(mode!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING || (ulong)OrderGetInteger(ORDER_MAGIC)==InpMagic)
        { reason="existing_order_or_netting_ownership_conflict"; return false; }
     }
   return true;
  }
bool FilledDirection(const int direction)
  {
   for(int i=0;i<ArraySize(g_positions);i++)
     {
      datetime utc=0; string error="";
      if(g_positions[i].direction==direction && g_clock.BrokerToUTC(g_positions[i].entry_time,utc,error) && utc>=g_session.start_utc && utc<g_session.end_utc) return true;
     }
   return false;
  }
void DrawLine(const string name,const double price,const color colour)
  {
   if(!InpShowVisuals || !MQLInfoInteger(MQL_VISUAL_MODE)) return;
   string key=g_prefix+name;
   if(ObjectFind(0,key)<0) ObjectCreate(0,key,OBJ_HLINE,0,0,price);
   ObjectSetDouble(0,key,OBJPROP_PRICE,price); ObjectSetInteger(0,key,OBJPROP_COLOR,colour);
  }
void DrawEntry(const BVSignal &s,const BVPlan &p)
  {
   if(!InpShowVisuals || !MQLInfoInteger(MQL_VISUAL_MODE)) return;
   string key=g_prefix+"ENTRY_"+IntegerToString((long)s.reclaim_time)+"_"+IntegerToString(s.direction);
   ObjectCreate(0,key,OBJ_ARROW,0,TimeCurrent(),p.actual_entry);
   ObjectSetInteger(0,key,OBJPROP_ARROWCODE,s.direction>0?233:234);
   ObjectSetInteger(0,key,OBJPROP_COLOR,s.direction>0?clrLime:clrTomato);
   DrawLine("SL_"+IntegerToString((long)s.reclaim_time),p.sl,clrRed);
   DrawLine("TP_"+IntegerToString((long)s.reclaim_time),p.tp,clrLime);
  }

bool SetSession(const BVSession &session)
  {
   if(g_session.id==session.id) return true;
   g_session=session; BVResetSetup(g_long,1); BVResetSetup(g_short,-1);
   string error=""; BVSession prior; ZeroMemory(g_profile);
   if(!g_clock.PreviousSession(session,prior,error)) { g_profile.reason="profile_time_mapping_invalid: "+error; g_fatal=g_profile.reason; LogSimple("PROFILE","REJECTED",g_profile.reason,TimeCurrent()); return false; }
   g_profile.session=prior;
   MqlRates bars[]; ArraySetAsSeries(bars,false);
   int count=CopyRates(_Symbol,PERIOD_M1,prior.start_broker,prior.end_broker-1,bars);
   BVProfileConfig cfg; cfg.rows=InpProfileRows; cfg.value_fraction=InpValueAreaPercent/100.0; cfg.volume_mode=InpVolumeMode;
   cfg.min_bars=(int)MathMax(InpMinProfileM1Bars,MathCeil((double)(prior.end_utc-prior.start_utc)/60.0*InpMinProfileCoveragePercent/100.0)); cfg.max_gap_minutes=InpMaxProfileGapMinutes; cfg.max_edge_gap_minutes=InpMaxProfileEdgeGapMinutes;
   if(count<=0) { g_profile.reason="missing_previous_session_M1_history"; LogSimple("PROFILE","REJECTED",g_profile.reason,TimeCurrent()); return false; }
   // Every contributing timestamp must have a unique historical UTC mapping.
   for(int i=0;i<count;i++)
     {
      datetime utc=0;
      if(!g_clock.BrokerToUTC(bars[i].time,utc,error) || utc<prior.start_utc || utc+60>prior.end_utc)
        { g_profile.reason="profile_time_mapping_invalid: "+error; g_fatal=g_profile.reason; LogSimple("PROFILE","REJECTED",g_profile.reason,TimeCurrent()); return false; }
     }
   if(!BVBuildProfile(bars,prior,cfg,g_spec.tick,g_profile,error))
     { LogSimple("PROFILE","REJECTED",error,TimeCurrent(),StringFormat("available=%d required=%d calendar_coverage_percent=%.4f",count,cfg.min_bars,100.0*count*60.0/(prior.end_utc-prior.start_utc))); return false; }
   Print("Frozen profile ",prior.id," -> ",session.id," ",BVSourceName(g_profile.source)," ",g_profile.source_note);
   LogSimple("PROFILE","ACCEPTED","previous_completed_session_frozen",TimeCurrent(),StringFormat("bars=%d input=%.10f allocated=%.10f rows=%d",g_profile.bar_count,g_profile.total_volume,g_profile.allocated_volume,g_profile.rows));
   DrawLine("VAL",g_profile.val,clrDodgerBlue); DrawLine("VAH",g_profile.vah,clrOrange); DrawLine("POC",g_profile.poc,clrSilver);
   return true;
  }
void SubmitSignal(BVSignal &signal)
  {
   BVPlan plan; ZeroMemory(plan); string reason="",label=""; datetime now=TimeCurrent(),utc=0;
   string key=g_session.id+"|"+IntegerToString(signal.direction)+"|"+IntegerToString((long)signal.reclaim_time);
   if(g_replay) return;
   if(g_journal.Has("ATTEMPT",key)) { LogSignal("ENTRY","REJECTED","duplicate_attempt_blocked",now,signal,plan); return; }
   // Consume the confirmation durably before any path can submit an order.
   if(!Durable("ATTEMPT",key)) return;
   int shift=iBarShift(_Symbol,InpSignalTimeframe,signal.reclaim_time,true); double atr[];
   if(shift<1 || CopyBuffer(g_atr,0,shift,1,atr)!=1 || atr[0]<=0 || !MathIsValidNumber(atr[0])) reason="closed_reclaim_ATR_unavailable";
   else { signal.atr=atr[0]; signal.buffer=MathMax(InpBufferTicks*g_spec.tick,InpATRBufferFraction*signal.atr); }
   if(reason=="" && !g_clock.BrokerToUTC(now,utc,reason)) reason="entry_time_mapping_invalid: "+reason;
   if(reason=="" && (now<signal.entry_due || now-signal.entry_due>InpMaxEntryDelaySeconds || iTime(_Symbol,InpSignalTimeframe,0)!=signal.entry_due)) reason="stale_signal_outside_next_bar_or_delay";
   BVSession current;
   if(reason=="" && (!g_clock.SessionAtUTC(utc,current,reason) || current.id!=g_session.id)) reason="setup_cannot_cross_session_boundary";
   if(reason=="" && !g_clock.InWindow(utc,InpEntryStartNYMinutes,InpEntryEndNYMinutes)) reason="outside_NY_entry_window";
   if(reason=="" && InpForceExit && g_clock.AtOrAfterNY(utc,InpForceExitNYMinutes)) reason="past_forced_exit_time";
   if(reason=="" && IsBlackout(utc,label)) reason="manual_UTC_blackout: "+label;
   if(reason=="" && (g_locked || g_fatal!="")) reason="daily_or_operational_lockout: "+g_fatal;
   if(reason=="" && !PositionRestriction(reason)) { }
   if(reason=="" && FilledDirection(signal.direction)) reason="direction_already_filled_this_profile_session";
   MqlTick tick; ZeroMemory(tick);
   if(reason=="" && (!BVReadSymbol(g_spec,reason) || !SymbolInfoTick(_Symbol,tick))) reason="symbol_or_quote_unavailable: "+reason;
   if(reason=="" && !BVBuildPlan(signal,g_profile,tick,g_spec,InpRiskPercent,InpMinRewardRisk,InpCommissionRoundTurnPerLot,InpSlippageTicksPerSide,InpMaxSpreadPoints,plan)) reason=plan.reason;
   if(reason!="") { LogSignal("ENTRY","REJECTED",reason,now,signal,plan); return; }
   MqlTradeRequest request={}; MqlTradeCheckResult check={}; MqlTradeResult result={};
   request.action=TRADE_ACTION_DEAL; request.magic=InpMagic; request.symbol=_Symbol; request.volume=plan.volume;
   request.type=signal.direction>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL; request.price=plan.entry; request.sl=plan.sl; request.tp=plan.tp;
   request.deviation=InpOrderDeviationPoints; request.comment="BV_"+IntegerToString((long)signal.reclaim_time);
   if(!BVFillMode(g_spec,request.type_filling,reason)) { LogSignal("ENTRY","REJECTED",reason,now,signal,plan); return; }
   if(!OrderCheck(request,check) || (check.retcode!=0 && check.retcode!=TRADE_RETCODE_DONE))
     { LogSignal("ENTRY","REJECTED","OrderCheck_failed",now,signal,plan,StringFormat("%u %s",check.retcode,check.comment)); return; }
   // No execution path is available outside the Strategy Tester.
   if(!MQLInfoInteger(MQL_TESTER)) return;
   bool sent=OrderSend(request,result); g_history_dirty=true;
   plan.actual_entry=result.price;
   bool accepted=sent && (result.retcode==TRADE_RETCODE_DONE || result.retcode==TRADE_RETCODE_DONE_PARTIAL || result.retcode==TRADE_RETCODE_PLACED);
   LogSignal("ENTRY",accepted?"SUBMITTED":"REJECTED",accepted?"market_request_accepted":"OrderSend_rejected",now,signal,plan,StringFormat("retcode=%u deal=%I64u order=%I64u %s",result.retcode,result.deal,result.order,result.comment));
   if(accepted) DrawEntry(signal,plan);
   SyncHistory();
  }
void StateEvent(const BVSetup &setup,const BVSignal &signal,const string event,const MqlRates &bar)
  {
   if(event=="") return;
   BVSignal s=signal; BVPlan p; ZeroMemory(p);
   // The core snapshots an excursion BEFORE clearing invalidated live state.
   // Preserve that snapshot so rejection logs retain their original evidence.
   if(s.reclaim_volume==0) s.reclaim_volume=BVBarVolume(bar,g_profile.source);
   LogSignal("SETUP",signal.valid?"CONFIRMED":"STATE",event,bar.time,s,p);
  }
void ProcessBar(const MqlRates &previous,const MqlRates &bar)
  {
   string error=""; datetime open_utc=0,close_utc=0; BVSession session,at_close;
   if(!g_clock.BrokerToUTC(bar.time,open_utc,error) || !g_clock.BrokerToUTC(bar.time+g_tf,close_utc,error) ||
      !g_clock.SessionAtUTC(open_utc,session,error) || !g_clock.SessionAtUTC(close_utc-1,at_close,error))
     { g_fatal="ambiguous_or_missing_historical_time_mapping: "+error; g_profile.valid=false; g_profile.reason=g_fatal; BVResetSetup(g_long,1); BVResetSetup(g_short,-1); LogSimple("CANDLE","REJECTED",g_fatal,bar.time); return; }
   SetSession(session);
   if(!g_profile.valid) return;
   if(session.id!=at_close.id || close_utc-open_utc!=g_tf) { BVResetSetup(g_long,1); BVResetSetup(g_short,-1); LogSimple("CANDLE","REJECTED","candle_straddles_session_or_offset_transition",bar.time); return; }
   if(BVBarVolume(bar,g_profile.source)<=0)
     { g_profile.valid=false; g_profile.reason="chosen_volume_unavailable_on_signal_candle_session_disabled"; BVResetSetup(g_long,1); BVResetSetup(g_short,-1); LogSimple("VOLUME","REJECTED",g_profile.reason,bar.time); return; }
   datetime previous_utc=0; BVSession prev_session;
   if(!g_clock.BrokerToUTC(previous.time,previous_utc,error) || !g_clock.SessionAtUTC(previous_utc,prev_session,error))
     { g_fatal="previous_candle_time_mapping_invalid: "+error; g_profile.valid=false; g_profile.reason=g_fatal; BVResetSetup(g_long,1); BVResetSetup(g_short,-1); LogSimple("CANDLE","REJECTED",g_fatal,bar.time); return; }
   // A contiguous prior close may reference the old session; the newly started
   // breakout and every pending excursion itself must belong to this session.
   if(previous.time+g_tf!=bar.time)
     { BVResetSetup(g_long,1); BVResetSetup(g_short,-1); LogSimple("CANDLE","REJECTED","missing_previous_signal_candle",bar.time); return; }
   BVSignal buy,sell; string long_event="",short_event="";
   BVAdvanceSetup(g_long,previous,bar,g_profile,InpMaxReclaimBars,InpRequireEngulfing,g_tf,buy,long_event);
   BVAdvanceSetup(g_short,previous,bar,g_profile,InpMaxReclaimBars,InpRequireEngulfing,g_tf,sell,short_event);
   StateEvent(g_long,buy,long_event,bar); StateEvent(g_short,sell,short_event,bar);
   if(buy.valid) SubmitSignal(buy);
   if(sell.valid) SubmitSignal(sell);
  }
bool ReplayInitial(string &reason)
  {
   datetime utc=0; BVSession session;
   if(!g_clock.BrokerToUTC(TimeCurrent(),utc,reason)||!g_clock.SessionAtUTC(utc,session,reason)) return false;
   SetSession(session);
   MqlRates bars[]; ArraySetAsSeries(bars,false);
   datetime current_open=iTime(_Symbol,InpSignalTimeframe,0);
   if(current_open<=0) { reason="Signal history unavailable at initialization"; return false; }
   int n=CopyRates(_Symbol,InpSignalTimeframe,session.start_broker-g_tf,current_open-1,bars);
   if(n<0) { reason="Signal warmup CopyRates not ready; preload broker history and retry"; return false; }
   datetime saved=g_cursor; g_replay=true;
   for(int i=0;i<n;i++)
     {
      datetime mapped=0,mapped_close=0;
      if(!g_clock.BrokerToUTC(bars[i].time,mapped,reason)||!g_clock.BrokerToUTC(bars[i].time+g_tf,mapped_close,reason)) { g_replay=false; return false; }
      if(i>0 && bars[i].time>=session.start_broker && bars[i].time+g_tf<=current_open && (saved==0 || bars[i].time<=saved)) ProcessBar(bars[i-1],bars[i]);
     }
   g_replay=false;
   // Cold attach establishes state from completed bars but cannot enter a past
   // confirmation. Restart reconstructs only as far as the durable cursor.
   if(saved==0 && n>0) g_cursor=bars[n-1].time;
   g_last_seen_closed=0;
   return true;
  }
void ProcessClosed(void)
  {
   datetime latest=iTime(_Symbol,InpSignalTimeframe,1);
   if(latest<=0 || latest<=g_cursor || latest==g_last_seen_closed) return;
   datetime start=g_cursor>0?g_cursor:latest-g_tf;
   MqlRates bars[]; ArraySetAsSeries(bars,false);
   int n=CopyRates(_Symbol,InpSignalTimeframe,start,latest,bars);
   if(n<2) { LogSimple("DATA","REJECTED","closed_candle_history_not_ready",TimeCurrent()); return; }
   for(int i=1;i<n;i++)
     {
      if(bars[i].time<=g_cursor || bars[i].time>latest || bars[i].time+g_tf>iTime(_Symbol,InpSignalTimeframe,0)) continue;
      ProcessBar(bars[i-1],bars[i]);
      g_cursor=bars[i].time; if(!Durable("CURSOR","last",IntegerToString((long)g_cursor))) return;
     }
   g_last_seen_closed=latest;
  }
void Display(const datetime utc)
  {
   if(!InpShowVisuals || !MQLInfoInteger(MQL_VISUAL_MODE)) return;
   Comment("Biltech Value Area Reversion | TESTER ONLY\n",_Symbol," | ",g_config,"\nProfile ",g_profile.session.id," -> ",g_session.id,
    " | ",BVSourceName(g_profile.source)," | ",g_profile.valid?"VALID":g_profile.reason,
    "\nVAL ",DoubleToString(g_profile.val,_Digits)," POC ",DoubleToString(g_profile.poc,_Digits)," VAH ",DoubleToString(g_profile.vah,_Digits),
    "\nLong ",g_long.active?"ACTIVE":"idle"," bars=",g_long.bars," weak=",g_long.weakened,
    " | Short ",g_short.active?"ACTIVE":"idle"," bars=",g_short.bars," weak=",g_short.weakened,
    "\nEntry window ",g_clock.InWindow(utc,InpEntryStartNYMinutes,InpEntryEndNYMinutes)?"OPEN":"closed",
    " | NY ",BVStamp(g_clock.UTCToNY(utc)),"\nDay ",g_day," ",g_locked?"LOCKED":"active"," base=",DoubleToString(g_day_equity,2),
    " net+float=",DoubleToString(g_realized+g_floating,2)," limit=",DoubleToString(g_day_equity*InpDailyLossPercent/100.0,2),"\n",g_fatal);
  }
int OnInit(void)
  {
   if(!MQLInfoInteger(MQL_TESTER)) { Print("RESEARCH EA: initialization refused outside MT5 Strategy Tester. No live/demo trading is enabled."); return INIT_FAILED; }
   if(InpRunId=="" || InpMagic==0 || StringLen(InpRunId)>50 || InpProfileRows<1 || InpProfileRows>10000 || InpValueAreaPercent<=0 || InpValueAreaPercent>100 ||
      InpMinProfileM1Bars<1 || InpMinProfileCoveragePercent<=0 || InpMinProfileCoveragePercent>100 || InpMaxProfileGapMinutes<0 || InpMaxProfileEdgeGapMinutes<0 || InpMaxReclaimBars<1 || InpATRPeriod<1 || InpBufferTicks<0 || InpATRBufferFraction<0 || (InpBufferTicks==0 && InpATRBufferFraction==0) ||
      InpRiskPercent<=0 || InpDailyLossPercent<=0 || InpMinRewardRisk<=0 || InpInitialDayEquity<0 || InpCommissionRoundTurnPerLot<0 || InpSlippageTicksPerSide<0 ||
      InpMaxSpreadPoints<=0 || InpMaxEntryDelaySeconds<0 || InpEntryStartNYMinutes<0 || InpEntryStartNYMinutes>1439 || InpEntryEndNYMinutes<0 || InpEntryEndNYMinutes>1439 || InpForceExitNYMinutes<0 || InpForceExitNYMinutes>1439)
     { Print("Invalid inputs. Set a positive broker-specific InpMaxSpreadPoints and review all ranges."); return INIT_PARAMETERS_INCORRECT; }
   g_tf=PeriodSeconds(InpSignalTimeframe);
   if(g_tf<60 || InpSignalTimeframe==PERIOD_CURRENT || g_tf>86400 || InpMaxEntryDelaySeconds>=g_tf)
     { Print("Select an explicit standard signal timeframe M1..D1; entry delay must be shorter than a bar."); return INIT_PARAMETERS_INCORRECT; }
   string reason=""; BVTimeConfig cfg;
   cfg.mode=InpSessionMode; cfg.broker_rule=InpBrokerOffsetRule; cfg.winter_minutes=InpBrokerWinterUTCMinutes;
   cfg.summer_minutes=InpBrokerSummerUTCMinutes; cfg.custom_boundary_minutes=InpCustomBoundaryMinutes;
   if(!g_clock.Init(cfg,reason)) { Print(reason); return INIT_PARAMETERS_INCORRECT; }
   if(reason!="") Print(reason);
   datetime utc=0;
   if(!g_clock.BrokerToUTC(TimeCurrent(),utc,reason)) { Print("Initialization time mapping failed: ",reason); return INIT_FAILED; }
   if(!BVReadSymbol(g_spec,reason)||!LoadBlackouts(reason)) { Print(reason); return INIT_FAILED; }
   // Include full exact config and blackout content digest in persistent identity.
   string config=ConfigText();
   for(int i=0;i<ArraySize(g_blackouts);i++) config+="|"+IntegerToString((long)g_blackouts[i].start)+"|"+IntegerToString((long)g_blackouts[i].end)+"|"+g_blackouts[i].label;
   g_config=SafeName(InpConfigLabel)+"_"+StringFormat("%08X",Hash(config));
   g_prefix="BV_"+StringFormat("%08X",Hash(InpRunId))+"_";
   string base="Biltech_"+SafeName(InpRunId)+"_"+SafeName(_Symbol)+"_"+U64(InpMagic);
   if(!g_journal.Open(base+"_journal.csv",TimeCurrent(),reason)) { Print(reason); return INIT_FAILED; }
   BVJournalRow meta;
   bool fresh_journal=!g_journal.Has("CONFIG","identity");
   if(g_journal.Find("CONFIG","identity",meta) && meta.a!=config)
     { Print("RunId journal belongs to different inputs. Choose a new InpRunId."); return INIT_FAILED; }
   if(!g_journal.Has("CONFIG","identity") && !Durable("CONFIG","identity",config)) return INIT_FAILED;
   g_signals=BVOpenCSV(base+"_signals.csv","event_id,event,status,reason,symbol,config_id,run_id,broker_time,utc,ny,session_id,profile_session_id,profile_start_broker,profile_end_broker,profile_start_utc,profile_end_utc,volume_source,volume_note,val,vah,poc,direction,breakout_broker,reclaim_broker,breakout_volume,reclaim_volume,bars_after_breakout,weakening,engulfing,excursion_extreme,atr,buffer,entry_due_broker,planned_entry,actual_entry,sl,tp,spread_points,estimated_rr,risk_budget,volume,initial_risk,annotation");
   g_trades=BVOpenCSV(base+"_trades.csv","event_id,event,position_id,deal_id,symbol,config_id,direction,broker_time,utc,ny,entry_utc,exit_utc,exit_ny,fill_price,volume,sl,tp,gross_pl,commission,swap,fees,net_pl,initial_risk,realized_r,holding_seconds,exit_reason,annotation");
   if(g_signals==INVALID_HANDLE || g_trades==INVALID_HANDLE) { Print("Cannot open output CSVs; check file permissions/duplicate instance"); return INIT_FAILED; }
   if(!LoadAudit(true,reason)||!LoadAudit(false,reason)) { Print("Audit recovery failed: ",reason); return INIT_FAILED; }
   if(fresh_journal && g_audit_records>0) { Print("Audit files exist without matching journal. Restore the complete run or choose a new RunId."); return INIT_FAILED; }
   if(!ValidateHistoryContinuation(reason)||!RecoverAudit()) { Print("Restart recovery failed: ",reason," ",g_fatal); return INIT_FAILED; }
   if(g_journal.Find("CURSOR","last",meta)) g_cursor=(datetime)StringToInteger(meta.a);
   g_atr=iATR(_Symbol,InpSignalTimeframe,InpATRPeriod);
   if(g_atr==INVALID_HANDLE) { Print("ATR handle creation failed"); return INIT_FAILED; }
   if(!NewDay(utc)||!SyncHistory()||!ReplayInitial(reason)) { Print("Initialization/warmup failed: ",reason," ",g_fatal); return INIT_FAILED; }
   if(g_fatal!="" || StringFind(g_profile.reason,"time_mapping_invalid")>=0) { Print(g_fatal," ",g_profile.reason); return INIT_FAILED; }
   LogSimple("INIT","ACCEPTED","tester_only_initialized",TimeCurrent(),StringFormat("tick=%.10f point=%.10f contract=%.10f min=%.8f max=%.8f step=%.8f stops=%d freeze=%d filling=%d calc=%d account_mode=%d",g_spec.tick,g_spec.point,g_spec.contract,g_spec.minimum,g_spec.maximum,g_spec.step,g_spec.stops,g_spec.freeze,g_spec.filling,g_spec.calc_mode,AccountInfoInteger(ACCOUNT_MARGIN_MODE)));
   g_initialized=true; return INIT_SUCCEEDED;
  }
void OnTick(void)
  {
   if(!g_initialized || !MQLInfoInteger(MQL_TESTER)) return;
   datetime utc=0; string reason="";
   if(!g_clock.BrokerToUTC(TimeCurrent(),utc,reason))
     { if(g_fatal=="") { g_fatal="current_tick_time_mapping_invalid: "+reason; LogSimple("CLOCK","LOCKED",g_fatal,TimeCurrent()); } CloseOwned("TIME_MAPPING_FAILURE"); return; }
   if(!NewDay(utc)) { CloseOwned("DAILY_STATE_FAILURE"); return; }
   SyncHistory(); ManageRisk(utc);
   ProcessClosed();
   // A boundary without a closed signal bar still replaces the frozen profile.
   BVSession current;
   if(g_clock.SessionAtUTC(utc,current,reason)) SetSession(current);
   else { g_fatal=reason; CloseOwned("SESSION_MAPPING_FAILURE"); }
   SyncHistory(); ManageRisk(utc); Display(utc);
  }
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   g_history_dirty=true;
   // Record each fill's monetary risk at its transaction, even when deal
   // arrival is between ticks. Never reconstruct it later at a changed rate.
   if(!g_initialized || trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0 || !HistoryDealSelect(trans.deal)) return;
   ulong deal=trans.deal;
   if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol || (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=InpMagic ||
      (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN || g_journal.Has("RISK",U64(deal))) return;
   ENUM_DEAL_TYPE side=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
   if(side!=DEAL_TYPE_BUY && side!=DEAL_TYPE_SELL) return;
   double entry=HistoryDealGetDouble(deal,DEAL_PRICE),sl=HistoryDealGetDouble(deal,DEAL_SL),volume=HistoryDealGetDouble(deal,DEAL_VOLUME);
   double loss=0,cost=0,risk=0;
   if(sl>0 && OrderCalcProfit(side==DEAL_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,volume,entry,sl,loss) &&
      BVCostPerLot(side==DEAL_TYPE_BUY?1:-1,entry,g_spec,InpCommissionRoundTurnPerLot,InpSlippageTicksPerSide,cost)) risk=MathMax(0,-loss)+volume*cost;
   Durable("RISK",U64(deal),BVNum(risk));
  }
void OnDeinit(const int reason)
  {
   if(g_initialized) { g_history_dirty=true; SyncHistory(); LogSimple("DEINIT","STOPPED",IntegerToString(reason),TimeCurrent()); }
   if(g_atr!=INVALID_HANDLE) IndicatorRelease(g_atr);
   if(g_signals!=INVALID_HANDLE) FileClose(g_signals); if(g_trades!=INVALID_HANDLE) FileClose(g_trades); g_journal.Close();
   if(g_prefix!="" && InpShowVisuals && MQLInfoInteger(MQL_VISUAL_MODE)) { ObjectsDeleteAll(0,g_prefix); Comment(""); }
  }
