#ifndef BV_EXECUTION_TESTS_MQH
#define BV_EXECUTION_TESTS_MQH
// Include BVExecution.mqh before this module. Fixtures call the same pure
// helpers as BVBuildPlan. They do not emulate or validate OrderCalcProfit,
// currency conversion, margin, OrderCheck, or broker execution.

void BVExecutionCheck(const bool passed,const string name,int &failures,int &checks)
  {
   checks++;
   if(!passed) { failures++; Print("BV EXECUTION TEST FAILED: ",name); }
  }
bool BVExecutionNear(const double actual,const double expected,const double tolerance=1.0e-8)
  { return MathAbs(actual-expected)<=tolerance; }
void BVExecutionFixture(BVSymbolSpec &s,MqlTick &tick)
  {
   ZeroMemory(s); ZeroMemory(tick);
   s.tick=0.1; s.point=0.1; s.contract=100.0; s.digits=1;
   s.minimum=0.1; s.maximum=100.0; s.step=0.1;
   s.order_mode=SYMBOL_ORDER_MARKET|SYMBOL_ORDER_SL|SYMBOL_ORDER_TP;
   s.trade_mode=SYMBOL_TRADE_MODE_FULL;
   s.execution=SYMBOL_TRADE_EXECUTION_MARKET;
   s.filling=SYMBOL_FILLING_FOK|SYMBOL_FILLING_IOC;
   tick.bid=100.0; tick.ask=100.2;
  }
int BVRunExecutionTests()
  {
   int failures=0,checks=0;
   BVSymbolSpec s; MqlTick tick;
   BVExecutionFixture(s,tick);
   double budget=0.0,volume=0.0,risk=0.0,spread=0.0;
   string reason="";
   bool valid=BVSizedRiskVolume(10000.0,0.25,100.0,s,budget,volume,risk,reason);
   BVExecutionCheck(valid && BVExecutionNear(budget,25.0) && BVExecutionNear(volume,0.2) &&
                     BVExecutionNear(risk,20.0),"risk budget rounds 0.25 lots down to 0.2 at 0.1 step",failures,checks);
   s.minimum=0.01; s.step=0.01;
   valid=BVSizedRiskVolume(10000.0,0.25,1000.0,s,budget,volume,risk,reason);
   BVExecutionCheck(valid && BVExecutionNear(volume,0.02) && BVExecutionNear(risk,20.0),
                     "different per-lot monetary loss and 0.01 volume step",failures,checks);
   s.minimum=0.1; s.step=0.1;
   valid=BVSizedRiskVolume(10000.0,0.25,50.0,s,budget,volume,risk,reason);
   BVExecutionCheck(valid && BVExecutionNear(volume,0.5) && BVExecutionNear(risk,25.0),
                     "exact supported volume uses available budget",failures,checks);
   s.minimum=1.0; s.step=1.0;
   valid=BVSizedRiskVolume(10000.0,0.25,7.0,s,budget,volume,risk,reason);
   BVExecutionCheck(valid && BVExecutionNear(volume,3.0) && BVExecutionNear(risk,21.0),
                     "integer lot step rounds down",failures,checks);
   s.minimum=0.25; s.step=0.25;
   valid=BVSizedRiskVolume(10000.0,0.25,30.0,s,budget,volume,risk,reason);
   BVExecutionCheck(valid && BVExecutionNear(volume,0.75) && BVExecutionNear(risk,22.5),
                     "non-decimal 0.25 lot step rounds down",failures,checks);
   s.minimum=0.1; s.step=0.1; s.maximum=1.2;
   valid=BVSizedRiskVolume(10000.0,1.0,10.0,s,budget,volume,risk,reason);
   BVExecutionCheck(valid && BVExecutionNear(volume,1.2) && BVExecutionNear(risk,12.0),
                     "broker maximum caps volume without increasing risk",failures,checks);
   s.maximum=100.0; s.volume_limit=0.7;
   valid=BVSizedRiskVolume(10000.0,1.0,10.0,s,budget,volume,risk,reason);
   BVExecutionCheck(valid && BVExecutionNear(volume,0.7) && BVExecutionNear(risk,7.0),
                     "directional volume limit caps this request",failures,checks);
   s.minimum=0.25; s.step=0.25; s.volume_limit=0.7;
   valid=BVSizedRiskVolume(10000.0,1.0,10.0,s,budget,volume,risk,reason);
   BVExecutionCheck(valid && BVExecutionNear(volume,0.5),
                     "volume limit is rounded down to supported step",failures,checks);
   s.minimum=0.1; s.step=0.1; s.volume_limit=0.0;
   valid=BVSizedRiskVolume(10000.0,0.05,100.0,s,budget,volume,risk,reason);
   BVExecutionCheck(!valid && BVExecutionNear(budget,5.0) && volume==0.0 &&
                     reason=="minimum_lot_exceeds_risk_or_rounding_invalid",
                     "minimum lot exceeding budget is skipped rather than rounded up",failures,checks);
   valid=BVSizedRiskVolume(10000.0,0.099999,100.0,s,budget,volume,risk,reason);
   BVExecutionCheck(!valid && volume==0.0,"sub-minimum exact risk budget never rounds up",failures,checks);
   valid=BVSizedRiskVolume(10000.0,0.1,100.0,s,budget,volume,risk,reason);
   BVExecutionCheck(valid && BVExecutionNear(volume,0.1) && BVExecutionNear(risk,10.0),
                     "minimum lot at exact risk budget is accepted",failures,checks);
   s.volume_limit=0.05;
   valid=BVSizedRiskVolume(10000.0,1.0,10.0,s,budget,volume,risk,reason);
   BVExecutionCheck(!valid && volume==0.0,"volume cap below minimum skips the request",failures,checks);
   s.volume_limit=0.0;
   BVExecutionCheck(!BVSizedRiskVolume(0.0,0.25,100.0,s,budget,volume,risk,reason) && volume==0.0,
                     "zero equity rejects sizing",failures,checks);
   BVExecutionCheck(!BVSizedRiskVolume(-100.0,0.25,100.0,s,budget,volume,risk,reason) && volume==0.0,
                     "negative equity rejects sizing",failures,checks);
   BVExecutionCheck(!BVSizedRiskVolume(10000.0,0.0,100.0,s,budget,volume,risk,reason),
                     "zero risk percent rejects sizing",failures,checks);
   BVExecutionCheck(!BVSizedRiskVolume(10000.0,0.25,0.0,s,budget,volume,risk,reason),
                     "zero monetary loss per lot rejects sizing",failures,checks);
   s.step=0.0;
   BVExecutionCheck(!BVSizedRiskVolume(10000.0,0.25,100.0,s,budget,volume,risk,reason),
                     "zero symbol volume step rejects sizing",failures,checks);

   BVExecutionFixture(s,tick);
   valid=BVCheckExecutionPrices(1,tick,s,99.0,102.0,2.0,spread,reason);
   BVExecutionCheck(valid && BVExecutionNear(spread,2.0),"spread exactly at configured maximum is accepted",failures,checks);
   tick.ask=100.21;
   BVExecutionCheck(!BVCheckExecutionPrices(1,tick,s,99.0,102.0,2.0,spread,reason) &&
                     reason=="spread_exceeds_max_points","spread above point limit is rejected",failures,checks);
   tick.ask=99.9;
   BVExecutionCheck(!BVCheckExecutionPrices(1,tick,s,99.0,102.0,2.0,spread,reason) &&
                     reason=="invalid_quote","inverted bid ask quote is rejected",failures,checks);
   tick.ask=100.2; tick.bid=0.0;
   BVExecutionCheck(!BVCheckExecutionPrices(1,tick,s,99.0,102.0,2.0,spread,reason) &&
                     reason=="invalid_quote","zero quote is rejected",failures,checks);
   tick.bid=100.0;
   BVExecutionCheck(!BVCheckExecutionPrices(1,tick,s,99.0,100.1,2.0,spread,reason) &&
                     reason=="stop_or_target_wrong_side_of_executable_entry",
                     "buy target below executable Ask is rejected",failures,checks);
   BVExecutionCheck(!BVCheckExecutionPrices(-1,tick,s,101.0,100.1,2.0,spread,reason) &&
                     reason=="stop_or_target_wrong_side_of_executable_entry",
                     "sell target above executable Bid is rejected",failures,checks);
   BVExecutionCheck(!BVCheckExecutionPrices(1,tick,s,100.3,102.0,2.0,spread,reason) &&
                     reason=="stop_or_target_wrong_side_of_executable_entry",
                     "buy stop above entry is rejected",failures,checks);
   s.stops=3;
   BVExecutionCheck(!BVCheckExecutionPrices(1,tick,s,99.8,102.0,2.0,spread,reason) &&
                     reason=="stop_or_freeze_distance","buy stop distance uses Bid rather than Ask",failures,checks);
   BVExecutionCheck(!BVCheckExecutionPrices(-1,tick,s,100.4,98.0,2.0,spread,reason) &&
                     reason=="stop_or_freeze_distance","sell stop distance uses Ask rather than Bid",failures,checks);
   BVExecutionCheck(!BVCheckExecutionPrices(1,tick,s,99.0,100.25,2.0,spread,reason) &&
                     reason=="stop_or_freeze_distance","buy target broker distance is enforced",failures,checks);
   BVExecutionCheck(BVCheckExecutionPrices(1,tick,s,99.7,100.3,2.0,spread,reason),
                     "stop and target exactly at broker distance are accepted",failures,checks);
   s.freeze=5;
   BVExecutionCheck(!BVCheckExecutionPrices(1,tick,s,99.6,102.0,2.0,spread,reason) &&
                     reason=="stop_or_freeze_distance","freeze distance larger than stops is enforced",failures,checks);
   BVExecutionCheck(BVCheckExecutionPrices(-1,tick,s,100.7,99.0,2.0,spread,reason),
                     "short stop exactly at freeze distance is accepted",failures,checks);
   s.freeze=0; s.stops=0;
   BVExecutionCheck(!BVCheckExecutionPrices(1,tick,s,0.0,102.0,2.0,spread,reason),
                     "zero SL cannot become an unprotected order",failures,checks);
   s.order_mode=SYMBOL_ORDER_MARKET|SYMBOL_ORDER_SL;
   BVExecutionCheck(!BVCheckExecutionPrices(1,tick,s,99.0,102.0,2.0,spread,reason) &&
                     reason=="symbol_requires_unsupported_order_protection",
                     "symbol without TP support rejects protected entry",failures,checks);
   s.order_mode=SYMBOL_ORDER_MARKET|SYMBOL_ORDER_SL|SYMBOL_ORDER_TP;
   s.trade_mode=SYMBOL_TRADE_MODE_SHORTONLY;
   BVExecutionCheck(!BVCheckExecutionPrices(1,tick,s,99.0,102.0,2.0,spread,reason) &&
                     reason=="symbol_direction_disabled","short-only symbol rejects buy",failures,checks);
   s.trade_mode=SYMBOL_TRADE_MODE_LONGONLY;
   BVExecutionCheck(!BVCheckExecutionPrices(-1,tick,s,101.0,98.0,2.0,spread,reason) &&
                     reason=="symbol_direction_disabled","long-only symbol rejects sell",failures,checks);
   s.trade_mode=SYMBOL_TRADE_MODE_FULL;
   BVExecutionCheck(!BVCheckExecutionPrices(0,tick,s,99.0,102.0,2.0,spread,reason),
                     "invalid signal direction cannot select an order side",failures,checks);

   ENUM_ORDER_TYPE_FILLING mode=ORDER_FILLING_RETURN;
   valid=BVFillMode(s,mode,reason);
   BVExecutionCheck(valid && mode==ORDER_FILLING_FOK,"FOK preferred when both flags are supported",failures,checks);
   s.filling=SYMBOL_FILLING_IOC;
   valid=BVFillMode(s,mode,reason);
   BVExecutionCheck(valid && mode==ORDER_FILLING_IOC,"IOC selected when FOK is unavailable",failures,checks);
   s.filling=0; s.execution=SYMBOL_TRADE_EXECUTION_REQUEST;
   valid=BVFillMode(s,mode,reason);
   BVExecutionCheck(valid && mode==ORDER_FILLING_RETURN,"RETURN allowed for Request execution",failures,checks);
   s.execution=SYMBOL_TRADE_EXECUTION_INSTANT;
   valid=BVFillMode(s,mode,reason);
   BVExecutionCheck(valid && mode==ORDER_FILLING_RETURN,"RETURN allowed for Instant execution",failures,checks);
   s.execution=SYMBOL_TRADE_EXECUTION_MARKET;
   BVExecutionCheck(!BVFillMode(s,mode,reason),"Market execution never falls back to RETURN",failures,checks);

   s.tick=0.25; s.digits=2; s.step=0.1;
   BVExecutionCheck(BVExecutionNear(BVFloorPrice(100.24,s),100.0) &&
                     BVExecutionNear(BVCeilPrice(100.01,s),100.25),"protective prices align to actual 0.25 tick",failures,checks);
   BVExecutionCheck(BVExecutionNear(BVFloorVolume(0.29,s),0.2),"volume rounding never rounds 0.29 up",failures,checks);
   BVExecutionCheck(BVExecutionNear(BVFloorVolume(0.2999999999999,s),0.2),
                     "numeric step tolerance never raises a truly sub-step request",failures,checks);
   PrintFormat("BV EXECUTION TESTS: %d checks, %d failures",checks,failures);
   return failures;
  }
#endif
