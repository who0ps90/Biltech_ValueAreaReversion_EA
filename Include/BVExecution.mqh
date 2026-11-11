#ifndef BV_EXECUTION_MQH
#define BV_EXECUTION_MQH
struct BVSymbolSpec
  {
   double tick,point,contract,minimum,maximum,step,volume_limit;
   int digits,stops,freeze;
   long filling,execution,order_mode,trade_mode,calc_mode;
  };
bool BVReadSymbol(BVSymbolSpec &s,string &reason)
  {
   s.tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   s.point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   s.contract=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE);
   s.minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   s.maximum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   s.step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   s.volume_limit=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_LIMIT);
   s.digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   s.stops=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   s.freeze=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   s.filling=SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   s.execution=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_EXEMODE);
   s.order_mode=SymbolInfoInteger(_Symbol,SYMBOL_ORDER_MODE);
   s.trade_mode=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
   s.calc_mode=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_CALC_MODE);
   if(s.tick<=0 || s.point<=0 || s.contract<=0 || s.minimum<=0 || s.maximum<s.minimum || s.step<=0)
     { reason="Missing or invalid symbol contract/volume/tick properties"; return false; }
   return true;
  }
double BVFloorPrice(const double p,const BVSymbolSpec &s)
  { return NormalizeDouble(MathFloor(p/s.tick+1e-9)*s.tick,s.digits); }
double BVCeilPrice(const double p,const BVSymbolSpec &s)
  { return NormalizeDouble(MathCeil(p/s.tick-1e-9)*s.tick,s.digits); }
double BVFloorVolume(const double volume,const BVSymbolSpec &s)
  {
   double rounded=NormalizeDouble(MathFloor((volume+1e-12)/s.step)*s.step,8);
   // The representation tolerance must never raise a truly sub-step request.
   if(rounded>volume) rounded=NormalizeDouble(rounded-s.step,8);
   return MathMax(0.0,rounded);
  }
bool BVFillMode(const BVSymbolSpec &s,ENUM_ORDER_TYPE_FILLING &mode,string &reason)
  {
   // Prefer FOK to avoid partial fills; IOC is still handled by deal accounting.
   if((s.filling & SYMBOL_FILLING_FOK)!=0) { mode=ORDER_FILLING_FOK; return true; }
   if((s.filling & SYMBOL_FILLING_IOC)!=0) { mode=ORDER_FILLING_IOC; return true; }
   if(s.execution!=SYMBOL_TRADE_EXECUTION_MARKET) { mode=ORDER_FILLING_RETURN; return true; }
   reason="No supported market-order filling mode"; return false;
  }

// Pure checks shared by production planning and native synthetic fixtures.
// Existing directional exposure is checked again by OrderCheck; volume_limit
// here is a conservative cap on this one requested order, not remaining capacity.
bool BVSizedRiskVolume(const double equity,const double risk_percent,const double loss_per_lot,
                       const BVSymbolSpec &s,double &risk_budget,double &volume,
                       double &initial_risk,string &reason)
  {
   risk_budget=0.0; volume=0.0; initial_risk=0.0; reason="";
   if(!MathIsValidNumber(equity) || equity<=0.0 || !MathIsValidNumber(risk_percent) || risk_percent<=0.0)
     { reason="nonpositive_or_invalid_equity_or_risk_percent"; return false; }
   if(!MathIsValidNumber(loss_per_lot) || loss_per_lot<=0.0)
     { reason="nonpositive_or_invalid_loss_per_lot"; return false; }
   if(!MathIsValidNumber(s.minimum) || !MathIsValidNumber(s.maximum) || !MathIsValidNumber(s.step) ||
      !MathIsValidNumber(s.volume_limit) || s.minimum<=0.0 || s.maximum<s.minimum || s.step<=0.0 || s.volume_limit<0.0)
     { reason="invalid_symbol_volume_properties"; return false; }
   risk_budget=equity*risk_percent/100.0;
   if(!MathIsValidNumber(risk_budget) || risk_budget<=0.0)
     { reason="nonpositive_or_invalid_risk_budget"; return false; }
   volume=BVFloorVolume(MathMin(risk_budget/loss_per_lot,s.maximum),s);
   if(s.volume_limit>0.0) volume=BVFloorVolume(MathMin(volume,s.volume_limit),s);
   initial_risk=loss_per_lot*volume;
   const double risk_epsilon=MathMax(1.0,MathAbs(risk_budget))*7.105427357601002e-15;
   // No upward adjustment to the broker minimum is ever permitted.
   if(!MathIsValidNumber(volume) || volume<=0.0 || !MathIsValidNumber(initial_risk) ||
      volume<s.minimum || initial_risk>risk_budget+risk_epsilon)
     { reason="minimum_lot_exceeds_risk_or_rounding_invalid"; return false; }
   reason="risk_volume_valid";
   return true;
  }

bool BVCheckExecutionPrices(const int direction,const MqlTick &tick,const BVSymbolSpec &s,
                            const double sl,const double tp,const double max_spread,
                            double &spread_points,string &reason)
  {
   spread_points=0.0; reason="";
   if((direction!=1 && direction!=-1) || !MathIsValidNumber(s.point) || s.point<=0.0 ||
      s.stops<0 || s.freeze<0 || !MathIsValidNumber(max_spread) || max_spread<=0.0 ||
      !MathIsValidNumber(sl) || !MathIsValidNumber(tp) || sl<=0.0 || tp<=0.0)
     { reason="invalid_execution_price_configuration"; return false; }
   if(!MathIsValidNumber(tick.ask) || !MathIsValidNumber(tick.bid) ||
      tick.ask<=0.0 || tick.bid<=0.0 || tick.ask<tick.bid)
     { reason="invalid_quote"; return false; }
   spread_points=(tick.ask-tick.bid)/s.point;
   if(spread_points>max_spread+1.0e-8)
     { reason="spread_exceeds_max_points"; return false; }
   if((s.order_mode & SYMBOL_ORDER_MARKET)==0 || (s.order_mode & SYMBOL_ORDER_SL)==0 ||
      (s.order_mode & SYMBOL_ORDER_TP)==0)
     { reason="symbol_requires_unsupported_order_protection"; return false; }
   if(s.trade_mode==SYMBOL_TRADE_MODE_DISABLED || s.trade_mode==SYMBOL_TRADE_MODE_CLOSEONLY ||
      (direction>0 && s.trade_mode==SYMBOL_TRADE_MODE_SHORTONLY) ||
      (direction<0 && s.trade_mode==SYMBOL_TRADE_MODE_LONGONLY))
     { reason="symbol_direction_disabled"; return false; }
   const double entry=(direction>0 ? tick.ask : tick.bid);
   if(direction*(entry-sl)<=0.0 || direction*(tp-entry)<=0.0)
     { reason="stop_or_target_wrong_side_of_executable_entry"; return false; }
   // Both SL and TP are checked from the closing quote: Bid for buys, Ask
   // for sells. Freeze distance is respected conservatively at submission.
   const double reference=(direction>0 ? tick.bid : tick.ask);
   const double distance=MathMax(s.stops,s.freeze)*s.point;
   if(direction*(reference-sl)<distance-1.0e-9 || direction*(tp-reference)<distance-1.0e-9)
     { reason="stop_or_freeze_distance"; return false; }
   reason="execution_prices_valid";
   return true;
  }
bool BVCostPerLot(const int dir,const double entry,const BVSymbolSpec &s,
                  const double commission,const double slippage_ticks,double &cost)
  {
   double slip=0;
   ENUM_ORDER_TYPE type=dir>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   // Two adverse sides are a conservative research allowance. Spread is already
   // represented by executable Ask/Bid and must not be added again.
   if(slippage_ticks>0 && !OrderCalcProfit(type,_Symbol,s.minimum,entry,
                         entry-dir*2.0*slippage_ticks*s.tick,slip)) return false;
   cost=commission+MathAbs(slip)/s.minimum;
   return MathIsValidNumber(cost) && cost>=0;
  }
bool BVBuildPlan(const BVSignal &signal,const BVProfile &profile,const MqlTick &tick,
                  const BVSymbolSpec &s,const double risk_percent,const double min_rr,
                  const double commission,const double slippage_ticks,const double max_spread,
                  BVPlan &p)
  {
   ZeroMemory(p);
   int d=signal.direction;
   const double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   p.entry=d>0 ? tick.ask : tick.bid;
   p.risk_budget=equity*risk_percent/100.0;
   p.sl=d>0 ? BVFloorPrice(signal.extreme-signal.buffer,s) : BVCeilPrice(signal.extreme+signal.buffer,s);
   p.tp=d>0 ? BVFloorPrice(profile.vah,s) : BVCeilPrice(profile.val,s);
   if(d*(signal.extreme-p.sl)<=0) { p.reason="SL_not_strictly_beyond_excursion_extreme"; return false; }
   if(!BVCheckExecutionPrices(d,tick,s,p.sl,p.tp,max_spread,p.spread_points,p.reason)) return false;
   ENUM_ORDER_TYPE type=d>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double loss=0,reward=0,cost=0;
   if(!OrderCalcProfit(type,_Symbol,s.minimum,p.entry,p.sl,loss) ||
      !OrderCalcProfit(type,_Symbol,s.minimum,p.entry,p.tp,reward) ||
      !BVCostPerLot(d,p.entry,s,commission,slippage_ticks,cost))
     { p.reason="OrderCalcProfit_failed"; return false; }
   double per_lot=-loss/s.minimum+cost;
   double net_reward=reward/s.minimum-cost;
   if(per_lot<=0 || net_reward<=0 || !MathIsValidNumber(per_lot) || !MathIsValidNumber(net_reward) ||
      !MathIsValidNumber(min_rr) || min_rr<=0.0) { p.reason="nonpositive_net_reward_or_risk"; return false; }
   p.rr=net_reward/per_lot;
   if(p.rr+1e-10<min_rr) { p.reason="insufficient_cost_adjusted_reward_risk"; return false; }
   if(!BVSizedRiskVolume(equity,risk_percent,per_lot,s,p.risk_budget,p.volume,p.initial_risk,p.reason)) return false;
   double margin=0;
   if(!OrderCalcMargin(type,_Symbol,p.volume,p.entry,margin) || margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE))
     { p.reason="insufficient_margin_or_margin_calculation_failed"; return false; }
   p.reason="plan_valid"; return true;
  }
#endif
