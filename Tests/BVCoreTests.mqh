#ifndef BV_CORE_TESTS_MQH
#define BV_CORE_TESTS_MQH
// Include BVTypes.mqh, BVProfile.mqh and BVSignal.mqh before this test module.
// Tests are pure synthetic OHLCV fixtures; they do not submit orders.

void BVCoreCheck(const bool passed,const string name,int &failures,int &checks)
  {
   checks++;
   if(!passed)
     {
      failures++;
      Print("BV CORE TEST FAILED: ",name);
     }
  }

bool BVCoreNear(const double actual,const double expected,const double tolerance=1.0e-8)
  { return MathAbs(actual-expected)<=tolerance; }

void BVCoreBar(MqlRates &bar,const datetime time,const double open,const double high,
               const double low,const double close,const long volume,const long real_volume=0)
  {
   ZeroMemory(bar);
   bar.time=time;
   bar.open=open;
   bar.high=high;
   bar.low=low;
   bar.close=close;
   bar.tick_volume=volume;
   bar.real_volume=real_volume;
  }

void BVCoreMirror(const MqlRates &source,MqlRates &target)
  {
   target=source;
   target.open=210.0-source.open;
   target.close=210.0-source.close;
   target.high=210.0-source.low;
   target.low=210.0-source.high;
  }

void BVCoreProfileTests(int &failures,int &checks)
  {
   const datetime start=D'2024.01.02 00:00:00';
   BVSession session;
   ZeroMemory(session);
   session.id="SYNTHETIC";
   session.start_broker=start;
   session.end_broker=start+180;
   BVProfileConfig cfg;
   cfg.rows=3;
   cfg.min_bars=3;
   cfg.max_gap_minutes=0;
   cfg.max_edge_gap_minutes=0;
   cfg.value_fraction=0.70;
   cfg.volume_mode=BV_TICK_VOLUME;
   MqlRates bars[];
   ArrayResize(bars,3);
   BVCoreBar(bars[0],start,100.0,101.0,100.0,100.5,30,3);
   BVCoreBar(bars[1],start+60,101.0,102.0,101.0,101.5,100,10);
   BVCoreBar(bars[2],start+120,102.0,103.0,102.0,102.5,30,3);
   BVProfile profile;
   string reason;
   bool built=BVBuildProfile(bars,session,cfg,1.0,profile,reason);
   BVCoreCheck(built,"profile builds from completed chronological bars",failures,checks);
   BVCoreCheck(built && profile.rows==3,"exact high edge does not create an extra bin",failures,checks);
   BVCoreCheck(built && BVCoreNear(profile.total_volume,160.0) &&
               BVCoreNear(profile.allocated_volume,160.0),"profile volume conservation",failures,checks);
   BVCoreCheck(built && BVCoreNear(profile.poc,101.5) && BVCoreNear(profile.val,100.0) &&
               BVCoreNear(profile.vah,102.0),"adjacent VA tie expands lower first",failures,checks);

   for(int i=0;i<3;i++) bars[i].tick_volume=10;
   cfg.value_fraction=1.0/3.0;
   built=BVBuildProfile(bars,session,cfg,1.0,profile,reason);
   BVCoreCheck(built && BVCoreNear(profile.poc,100.5) && BVCoreNear(profile.val,100.0) &&
               BVCoreNear(profile.vah,101.0),"POC ties choose lowest bin",failures,checks);
   MqlRates uniform[];
   ArrayResize(uniform,1);
   BVCoreBar(uniform[0],start,100.0,103.0,100.0,101.5,100);
   BVSession uniform_session=session;
   uniform_session.end_broker=start+60;
   BVProfileConfig uniform_cfg=cfg;
   uniform_cfg.min_bars=1;
   built=BVBuildProfile(uniform,uniform_session,uniform_cfg,1.0,profile,reason);
   BVCoreCheck(built && BVCoreNear(profile.poc,100.5) && BVCoreNear(profile.val,100.0) &&
               BVCoreNear(profile.vah,101.0),"fractional overlap residual preserves mathematical POC tie",failures,checks);
   cfg.value_fraction=1.0;
   built=BVBuildProfile(bars,session,cfg,1.0,profile,reason);
   BVCoreCheck(built && BVCoreNear(profile.val,100.0) && BVCoreNear(profile.vah,103.0),
               "100 percent value area contains full profile",failures,checks);

   cfg.rows=7;
   cfg.value_fraction=0.70;
   BVCoreBar(bars[0],start,100.03,100.47,100.03,100.25,17,3);
   BVCoreBar(bars[1],start+60,100.10,100.20,100.10,100.15,37,10);
   BVCoreBar(bars[2],start+120,100.20,100.20,100.20,100.20,11,3);
   built=BVBuildProfile(bars,session,cfg,0.05,profile,reason);
   BVCoreCheck(built && profile.rows<=cfg.rows && BVCoreNear(profile.total_volume,65.0) &&
               BVCoreNear(profile.allocated_volume,65.0),"overlap plus zero-range bars conserve volume",failures,checks);
   BVCoreCheck(built && BVCoreNear(profile.bin_origin/0.05,MathRound(profile.bin_origin/0.05)) &&
               BVCoreNear(profile.bin_width/0.05,MathRound(profile.bin_width/0.05)) &&
               BVCoreNear(profile.val/0.05,MathRound(profile.val/0.05)) &&
               BVCoreNear(profile.vah/0.05,MathRound(profile.vah/0.05)),
               "bin origin width and value edges are tick aligned",failures,checks);

   for(int i=0;i<3;i++) BVCoreBar(bars[i],start+i*60,100.0,100.0,100.0,100.0,14,2);
   cfg.rows=100;
   built=BVBuildProfile(bars,session,cfg,1.0,profile,reason);
   BVCoreCheck(built && profile.rows==1 && BVCoreNear(profile.val,100.0) &&
               BVCoreNear(profile.vah,101.0) && BVCoreNear(profile.total_volume,42.0),
               "degenerate flat session gets one tick bin",failures,checks);
   cfg.volume_mode=BV_AUTO;
   built=BVBuildProfile(bars,session,cfg,1.0,profile,reason);
   BVCoreCheck(built && profile.source==BV_REAL_VOLUME && BVCoreNear(profile.total_volume,6.0),
               "AUTO uses real only when every bar has positive real volume",failures,checks);
   bars[1].real_volume=0;
   built=BVBuildProfile(bars,session,cfg,1.0,profile,reason);
   BVCoreCheck(built && profile.source==BV_TICK_VOLUME && BVCoreNear(profile.total_volume,42.0) &&
               StringFind(profile.source_note,"WARNING")>=0,"AUTO consistent tick fallback is annotated",failures,checks);
   cfg.volume_mode=BV_REAL_VOLUME;
   BVCoreCheck(!BVBuildProfile(bars,session,cfg,1.0,profile,reason),
               "explicit real volume rejects one unavailable bar",failures,checks);
   cfg.volume_mode=BV_TICK_VOLUME;
   bars[1].tick_volume=0;
   BVCoreCheck(!BVBuildProfile(bars,session,cfg,1.0,profile,reason),
               "zero selected volume rejects entire profile",failures,checks);
   bars[1].tick_volume=14;
   bars[2].time=session.end_broker;
   BVCoreCheck(!BVBuildProfile(bars,session,cfg,1.0,profile,reason),
               "current or future session M1 bar is rejected",failures,checks);
   bars[2].time=start+120;
   bars[1].time=start;
   BVCoreCheck(!BVBuildProfile(bars,session,cfg,1.0,profile,reason),
               "duplicate nonchronological profile bar is rejected",failures,checks);
   bars[1].time=start+60;
   cfg.min_bars=4;
   BVCoreCheck(!BVBuildProfile(bars,session,cfg,1.0,profile,reason),
               "insufficient profile history is rejected",failures,checks);
   cfg.min_bars=1;
   session.end_broker=start+240;
   bars[2].time=start+180;
   BVCoreCheck(!BVBuildProfile(bars,session,cfg,1.0,profile,reason),
               "missing internal M1 minute is rejected at zero gap tolerance",failures,checks);
   cfg.max_gap_minutes=1;
   built=BVBuildProfile(bars,session,cfg,1.0,profile,reason);
   BVCoreCheck(built,"configured internal missing-minute tolerance is inclusive",failures,checks);
   session.end_broker=start+300;
   BVCoreCheck(!BVBuildProfile(bars,session,cfg,1.0,profile,reason),
               "missing edge M1 history is rejected",failures,checks);
   ArrayResize(bars,0);
   BVCoreCheck(!BVBuildProfile(bars,session,cfg,1.0,profile,reason),
               "empty profile history is rejected",failures,checks);
  }

void BVCoreSignalFixture(MqlRates &previous,MqlRates &breakout,MqlRates &weakening,
                         MqlRates &reclaim,const datetime start)
  {
   BVCoreBar(previous,start-900,102.0,103.0,100.0,101.0,100);
   BVCoreBar(breakout,start,100.0,101.0,96.0,98.0,100);
   BVCoreBar(weakening,start+900,98.0,99.0,95.0,97.0,50);
   BVCoreBar(reclaim,start+1800,96.0,103.0,94.0,102.0,150);
  }

void BVCoreSignalTests(int &failures,int &checks)
  {
   const datetime start=D'2024.01.03 10:00:00';
   BVProfile profile;
   ZeroMemory(profile);
   profile.valid=true;
   profile.val=100.0;
   profile.vah=110.0;
   profile.source=BV_TICK_VOLUME;
   BVSetup state;
   BVSignal signal;
   string event;
   MqlRates previous,breakout,weakening,reclaim;
   BVCoreSignalFixture(previous,breakout,weakening,reclaim,start);
   BVResetSetup(state,1);
   bool confirmed=BVAdvanceSetup(state,previous,breakout,profile,5,true,900,signal,event);
   BVCoreCheck(!confirmed && state.active && state.bars==0 && !state.weakened &&
               state.breakout_time==start,"breakout starts at bar zero without weakening",failures,checks);
   BVAdvanceSetup(state,breakout,weakening,profile,5,true,900,signal,event);
   BVCoreCheck(state.weakened && state.bars==1 && state.breakout_time==start &&
               BVCoreNear(state.breakout_volume,100.0),"outside bars retain initial breakout and allow later weakening",failures,checks);
   confirmed=BVAdvanceSetup(state,weakening,reclaim,profile,5,true,900,signal,event);
   BVCoreCheck(confirmed && signal.valid && signal.weakening && signal.engulfing && signal.bars==2 &&
               signal.entry_due==reclaim.time+900 && BVCoreNear(signal.extreme,94.0) && !state.active,
               "long reclaim confirms with inclusive excursion and next-bar entry time",failures,checks);
   confirmed=BVAdvanceSetup(state,weakening,reclaim,profile,5,true,900,signal,event);
   BVCoreCheck(!confirmed && event=="ignored_duplicate_or_out_of_order_bar" && !state.active,
               "duplicate confirmation cannot emit a second signal",failures,checks);

   // Reflect all prices around 105; every state and threshold must mirror.
   MqlRates short_previous,short_breakout,short_weakening,short_reclaim;
   BVCoreMirror(previous,short_previous);
   BVCoreMirror(breakout,short_breakout);
   BVCoreMirror(weakening,short_weakening);
   BVCoreMirror(reclaim,short_reclaim);
   BVResetSetup(state,-1);
   BVAdvanceSetup(state,short_previous,short_breakout,profile,5,true,900,signal,event);
   BVAdvanceSetup(state,short_breakout,short_weakening,profile,5,true,900,signal,event);
   confirmed=BVAdvanceSetup(state,short_weakening,short_reclaim,profile,5,true,900,signal,event);
   BVCoreCheck(confirmed && signal.direction==-1 && signal.bars==2 && signal.weakening &&
               signal.engulfing && BVCoreNear(signal.extreme,116.0),"short rules mirror long rules",failures,checks);

   BVResetSetup(state,1);
   BVAdvanceSetup(state,previous,breakout,profile,5,true,900,signal,event);
   MqlRates last=breakout,current;
   for(int i=1;i<=4;i++)
     {
      BVCoreBar(current,start+i*900,98.0,99.0,95.0,97.0,50);
      BVAdvanceSetup(state,last,current,profile,5,true,900,signal,event);
      last=current;
     }
   reclaim.time=start+5*900;
   confirmed=BVAdvanceSetup(state,last,reclaim,profile,5,true,900,signal,event);
   BVCoreCheck(confirmed && signal.bars==5,"reclaim on bar five is accepted",failures,checks);
   BVResetSetup(state,1);
   BVAdvanceSetup(state,previous,breakout,profile,5,true,900,signal,event);
   last=breakout;
   for(int i=1;i<=5;i++)
     {
      BVCoreBar(current,start+i*900,98.0,99.0,95.0,97.0,50);
      BVAdvanceSetup(state,last,current,profile,5,true,900,signal,event);
      last=current;
     }
   reclaim.time=start+6*900;
   confirmed=BVAdvanceSetup(state,last,reclaim,profile,5,true,900,signal,event);
   BVCoreCheck(!confirmed && !state.active && event=="reclaim_deadline_expired",
               "reclaim on bar six is rejected",failures,checks);

   BVCoreSignalFixture(previous,breakout,weakening,reclaim,start);
   BVResetSetup(state,1);
   BVAdvanceSetup(state,previous,breakout,profile,5,true,900,signal,event);
   reclaim.time=start+900;
   confirmed=BVAdvanceSetup(state,breakout,reclaim,profile,5,true,900,signal,event);
   BVCoreCheck(!confirmed && !state.active && event=="unconfirmed_reentry_no_prior_weakening",
               "breakout cannot provide its own weakening for bar-one reclaim",failures,checks);
   weakening.time=start+1800;
   BVAdvanceSetup(state,reclaim,weakening,profile,5,true,900,signal,event);
   BVCoreCheck(state.active && state.breakout_time==weakening.time,
               "fresh crossing after invalidation creates a new excursion",failures,checks);

   BVCoreSignalFixture(previous,breakout,weakening,reclaim,start);
   BVResetSetup(state,1);
   BVAdvanceSetup(state,previous,breakout,profile,5,true,900,signal,event);
   weakening.tick_volume=100;
   BVAdvanceSetup(state,breakout,weakening,profile,5,true,900,signal,event);
   BVCoreCheck(!state.weakened,"weakening volume must be strictly lower",failures,checks);
   BVResetSetup(state,1);
   BVAdvanceSetup(state,previous,breakout,profile,5,true,900,signal,event);
   weakening.tick_volume=50;
   BVAdvanceSetup(state,breakout,weakening,profile,5,true,900,signal,event);
   reclaim.tick_volume=100;
   confirmed=BVAdvanceSetup(state,weakening,reclaim,profile,5,true,900,signal,event);
   BVCoreCheck(!confirmed && !state.active && event=="unconfirmed_reentry_volume_not_greater",
               "reclaim volume must be strictly greater",failures,checks);

   BVCoreSignalFixture(previous,breakout,weakening,reclaim,start);
   BVResetSetup(state,1);
   BVAdvanceSetup(state,previous,breakout,profile,5,true,900,signal,event);
   BVAdvanceSetup(state,breakout,weakening,profile,5,true,900,signal,event);
   reclaim.open=97.5;
   confirmed=BVAdvanceSetup(state,weakening,reclaim,profile,5,true,900,signal,event);
   BVCoreCheck(!confirmed && event=="unconfirmed_reentry_no_body_engulf",
               "body engulf requirement rejects an incomplete engulf",failures,checks);
   BVResetSetup(state,1);
   BVAdvanceSetup(state,previous,breakout,profile,5,false,900,signal,event);
   BVAdvanceSetup(state,breakout,weakening,profile,5,false,900,signal,event);
   confirmed=BVAdvanceSetup(state,weakening,reclaim,profile,5,false,900,signal,event);
   BVCoreCheck(confirmed && !signal.engulfing,"optional engulf input disables only body coverage test",failures,checks);

   BVCoreSignalFixture(previous,breakout,weakening,reclaim,start);
   BVResetSetup(state,1);
   BVAdvanceSetup(state,previous,breakout,profile,5,true,900,signal,event);
   weakening.tick_volume=0;
   BVAdvanceSetup(state,breakout,weakening,profile,5,true,900,signal,event);
   BVCoreCheck(!state.active && event=="selected_signal_volume_missing_or_zero",
               "zero selected signal volume invalidates active excursion",failures,checks);
   BVResetSetup(state,1);
   profile.source=BV_REAL_VOLUME;
   BVAdvanceSetup(state,previous,breakout,profile,5,true,900,signal,event);
   BVCoreCheck(!state.active && event=="selected_signal_volume_missing_or_zero",
               "frozen real signal source never falls back bar by bar",failures,checks);
   profile.source=BV_TICK_VOLUME;
   BVResetSetup(state,1);
   BVAdvanceSetup(state,previous,breakout,profile,5,true,900,signal,event);
   BVCoreBar(current,start+900,98.0,112.0,97.0,111.0,150);
   BVAdvanceSetup(state,breakout,current,profile,5,true,900,signal,event);
   BVCoreCheck(!state.active && event=="opposite_value_boundary_reached",
               "opposite value boundary invalidates excursion",failures,checks);
   BVResetSetup(state,1);
   BVAdvanceSetup(state,previous,breakout,profile,5,true,900,signal,event);
   BVCoreBar(current,start+900,98.0,101.0,97.0,100.0,150);
   confirmed=BVAdvanceSetup(state,breakout,current,profile,5,true,900,signal,event);
   BVCoreCheck(!confirmed && !state.active,"boundary equality cannot confirm and ends excursion",failures,checks);
   BVResetSetup(state,1);
   BVCoreCheck(!state.active && state.last_bar_time==0 && !state.weakened,
               "session reset clears state and closed-bar cursor",failures,checks);
  }

int BVRunCoreTests()
  {
   int failures=0,checks=0;
   BVCoreProfileTests(failures,checks);
   BVCoreSignalTests(failures,checks);
   PrintFormat("BV CORE TESTS: %d checks, %d failures",checks,failures);
   return failures;
  }
#endif
