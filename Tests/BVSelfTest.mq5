#property strict
#property version "1.00"
#property description "Deterministic Biltech core/calendar fixtures. Tester only; never submits orders."
#include "../Include/BVTypes.mqh"
#include "../Include/BVTime.mqh"
#include "../Include/BVProfile.mqh"
#include "../Include/BVSignal.mqh"
#include "../Include/BVExecution.mqh"
#include "BVCoreTests.mqh"
#include "BVTimeTests.mqh"
#include "BVExecutionTests.mqh"
#include "BVJournalTests.mqh"
int g_failures=0;
int OnInit(void)
  {
   if(!MQLInfoInteger(MQL_TESTER)) { Print("Run this no-order fixture EA in Strategy Tester"); return INIT_FAILED; }
   g_failures=BVRunCoreTests()+BVRunTimeTests()+BVRunExecutionTests()+BVRunJournalTests();
   PrintFormat("BILTECH SELFTEST: %d failures.",g_failures);
   return g_failures==0?INIT_SUCCEEDED:INIT_FAILED;
  }
void OnTick(void) { }
double OnTester(void) { return g_failures==0?1.0:0.0; }
