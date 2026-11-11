#ifndef BV_TIME_TESTS_MQH
#define BV_TIME_TESTS_MQH
#include "../Include/BVTime.mqh"

void BVTimeExpect(const bool condition,const string label,int &checks,int &failures)
  {
   checks++;
   if(condition) return;
   failures++;
   Print("TIME TEST FAILED: ",label);
  }

// Deterministic fixtures only. Returns failures, not checks. Invoke from the
// dedicated tester script/EA; these tests never submit trading requests.
int BVRunTimeTests()
  {
   int checks=0,failures=0;
   string reason="",id="";
   datetime result=0,day=0;
   BVSession current,previous;
   BVClock clock;
   BVTimeConfig cfg;
   cfg.mode=BV_NEW_YORK_SESSION;
   cfg.broker_rule=BV_OFFSET_UNCONFIGURED;
   cfg.winter_minutes=0; cfg.summer_minutes=60;
   cfg.custom_boundary_minutes=0;
   BVTimeExpect(!clock.Init(cfg,reason),"unconfigured mapping rejected",checks,failures);
   cfg.broker_rule=BV_OFFSET_FIXED;
   BVTimeExpect(clock.Init(cfg,reason),"fixed UTC mapping initializes",checks,failures);
   BVTimeExpect(clock.UTCToNY(D'2007.03.11 06:59:59')==D'2007.03.11 01:59:59',"first supported US spring, before",checks,failures);
   BVTimeExpect(clock.UTCToNY(D'2007.03.11 07:00:00')==D'2007.03.11 03:00:00',"first supported US spring, after",checks,failures);
   BVTimeExpect(clock.UTCToNY(D'2024.11.03 05:59:59')==D'2024.11.03 01:59:59',"NY autumn, before",checks,failures);
   BVTimeExpect(clock.UTCToNY(D'2024.11.03 06:00:00')==D'2024.11.03 01:00:00',"NY autumn, after",checks,failures);
   BVTimeExpect(clock.UTCToNY(D'2099.07.01 12:00:00')==D'2099.07.01 08:00:00',"last supported year summer",checks,failures);
   BVTimeExpect(!clock.NYToUTC(D'2024.03.10 02:30:00',result,reason),"NY spring gap rejected",checks,failures);
   BVTimeExpect(!clock.NYToUTC(D'2024.11.03 01:30:00',result,reason),"NY autumn fold rejected",checks,failures);
   BVTimeExpect(clock.NYToUTC(D'2024.03.10 03:00:00',result,reason) && result==D'2024.03.10 07:00:00',"NY unique time maps",checks,failures);
   BVTimeExpect(clock.SessionAtUTC(D'2024.03.10 12:00:00',current,reason) && current.id=="2024-03-09" && current.end_utc-current.start_utc==23*3600,"NY spring session is 23 hours",checks,failures);
   BVTimeExpect(clock.SessionAtUTC(D'2024.11.03 12:00:00',current,reason) && current.id=="2024-11-02" && current.end_utc-current.start_utc==25*3600,"NY autumn session is 25 hours",checks,failures);
   BVTimeExpect(clock.PreviousSession(current,previous,reason) && previous.end_utc==current.start_utc && previous.id=="2024-11-01","previous session is contiguous",checks,failures);
   BVTimeExpect(clock.SessionAtUTC(D'2024.07.01 22:00:00',current,reason) && current.id=="2024-07-01","18:00 boundary belongs to new NY session",checks,failures);
   BVTimeExpect(clock.SessionAtUTC(D'2024.07.01 21:59:59',current,reason) && current.id=="2024-06-30","instant before boundary belongs to prior NY session",checks,failures);
   BVTimeExpect(clock.NYDay(D'2024.03.10 12:00:00',id,day,reason) && id=="2024-03-10" && day==D'2024.03.10 05:00:00',"spring NY risk day begins in standard time",checks,failures);
   BVTimeExpect(clock.NYDay(D'2024.11.03 12:00:00',id,day,reason) && day==D'2024.11.03 04:00:00',"autumn NY risk day begins in daylight time",checks,failures);
   BVTimeExpect(clock.InWindow(D'2024.07.01 13:45:00',585,690),"window start inclusive",checks,failures);
   BVTimeExpect(!clock.InWindow(D'2024.07.01 15:30:00',585,690),"window end exclusive",checks,failures);
   BVTimeExpect(clock.InWindow(D'2024.07.02 05:00:00',1320,120),"overnight window early segment",checks,failures);
   BVTimeExpect(!clock.InWindow(D'2024.07.02 06:00:00',1320,120),"overnight end exclusive",checks,failures);
   BVTimeExpect(clock.InWindow(D'2024.07.01 12:00:00',0,0),"equal endpoints explicitly all day",checks,failures);
   BVTimeExpect(clock.AtOrAfterNY(D'2024.07.01 19:55:00',955),"forced exit cutoff inclusive",checks,failures);
   BVTimeExpect(!clock.AtOrAfterNY(D'2024.07.01 19:54:59',955),"before forced exit cutoff",checks,failures);
   BVTimeExpect(!clock.BrokerToUTC(D'2006.12.31 12:00:00',result,reason),"unsupported year rejected",checks,failures);
   cfg.winter_minutes=120; cfg.summer_minutes=180;
   cfg.broker_rule=BV_OFFSET_EU;
   BVTimeExpect(clock.Init(cfg,reason),"EU mapping initializes",checks,failures);
   BVTimeExpect(clock.BrokerToUTC(D'2024.03.31 02:59:59',result,reason) && result==D'2024.03.31 00:59:59',"EU winter last second",checks,failures);
   BVTimeExpect(clock.BrokerToUTC(D'2024.03.31 04:00:00',result,reason) && result==D'2024.03.31 01:00:00',"EU summer first second",checks,failures);
   BVTimeExpect(!clock.BrokerToUTC(D'2024.03.31 03:30:00',result,reason),"EU broker spring gap rejected",checks,failures);
   BVTimeExpect(!clock.BrokerToUTC(D'2024.10.27 03:30:00',result,reason) && StringFind(reason,"Ambiguous")>=0,"EU broker autumn fold rejected with reason",checks,failures);
   BVTimeExpect(clock.UTCToBroker(D'2024.10.27 00:30:00',result,reason) && result==D'2024.10.27 03:30:00',"UTC forward conversion remains defined inside fold",checks,failures);
   cfg.broker_rule=BV_OFFSET_US;
   BVTimeExpect(clock.Init(cfg,reason),"US mapping initializes",checks,failures);
   BVTimeExpect(clock.BrokerToUTC(D'2024.03.10 08:59:59',result,reason) && result==D'2024.03.10 06:59:59',"US rule uses NY transition instant",checks,failures);
   BVTimeExpect(!clock.BrokerToUTC(D'2024.03.10 09:30:00',result,reason),"US broker spring gap rejected",checks,failures);
   BVTimeExpect(!clock.BrokerToUTC(D'2024.11.03 08:30:00',result,reason),"US broker autumn fold rejected",checks,failures);
   cfg.mode=BV_BROKER_CUSTOM_SESSION;
   cfg.broker_rule=BV_OFFSET_EU;
   cfg.custom_boundary_minutes=0;
   BVTimeExpect(clock.Init(cfg,reason) && clock.SessionAtUTC(D'2024.10.27 12:00:00',current,reason) && current.end_utc-current.start_utc==25*3600,"custom broker midnight autumn session",checks,failures);
   cfg.custom_boundary_minutes=210;
   BVTimeExpect(clock.Init(cfg,reason) && !clock.SessionAtUTC(D'2024.10.27 12:00:00',current,reason),"ambiguous custom boundary rejected",checks,failures);
   cfg.mode=BV_NEW_YORK_SESSION;
   cfg.broker_rule=BV_OFFSET_FIXED;
   cfg.winter_minutes=345;
   BVTimeExpect(clock.Init(cfg,reason) && clock.BrokerToUTC(D'2024.07.01 17:45:00',result,reason) && result==D'2024.07.01 12:00:00',"fractional-hour fixed offset",checks,failures);
   cfg.winter_minutes=841;
   BVTimeExpect(!clock.Init(cfg,reason),"out of range offset rejected",checks,failures);
   cfg.winter_minutes=120; cfg.summer_minutes=240; cfg.broker_rule=BV_OFFSET_EU;
   BVTimeExpect(!clock.Init(cfg,reason),"invalid seasonal difference rejected",checks,failures);
   PrintFormat("Time self-tests: %d checks, %d failures.",checks,failures);
   return failures;
  }
#endif
