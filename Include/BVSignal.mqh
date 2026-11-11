#ifndef BV_SIGNAL_MQH
#define BV_SIGNAL_MQH
#include "BVTypes.mqh"

void BVResetSetup(BVSetup &state,const int direction)
  {
   ZeroMemory(state);
   state.direction=direction;
  }

void BVSetupSnapshot(const BVSetup &state,BVSignal &signal)
  {
   signal.direction=state.direction;
   signal.bars=state.bars;
   signal.weakening=state.weakened;
   signal.breakout_time=state.breakout_time;
   signal.breakout_volume=state.breakout_volume;
   signal.extreme=state.extreme;
  }

void BVEndSetup(BVSetup &state)
  {
   const int direction=state.direction;
   const datetime last_bar_time=state.last_bar_time;
   BVResetSetup(state,direction);
   state.last_bar_time=last_bar_time;
  }

bool BVSignalOHLCValid(const MqlRates &bar)
  {
   return MathIsValidNumber(bar.open) && MathIsValidNumber(bar.close) &&
          MathIsValidNumber(bar.high) && MathIsValidNumber(bar.low) &&
          bar.high>=bar.low && bar.open>=bar.low && bar.open<=bar.high &&
          bar.close>=bar.low && bar.close<=bar.high;
  }

// One independent state per direction; caller resets it on profile-session
// changes. The last-bar guard also makes repeated calls for a closed bar inert.
// Returns true only on a newly confirmed reclaim; every other event is false.
bool BVAdvanceSetup(BVSetup &state,const MqlRates &previous,const MqlRates &bar,
                    const BVProfile &profile,const int max_bars,const bool require_engulf,
                    const int timeframe_seconds,BVSignal &signal,string &event)
  {
   ZeroMemory(signal);
   signal.direction=state.direction;
   event="";
   if(bar.time<=state.last_bar_time)
     {
      event="ignored_duplicate_or_out_of_order_bar";
      signal.reason=event;
      return false;
     }
   state.last_bar_time=bar.time;
   if(!profile.valid || !MathIsValidNumber(profile.val) || !MathIsValidNumber(profile.vah) ||
      profile.val>=profile.vah || (profile.source!=BV_TICK_VOLUME && profile.source!=BV_REAL_VOLUME) ||
      max_bars<1 || timeframe_seconds<1 || (state.direction!=1 && state.direction!=-1))
     {
      BVSetupSnapshot(state,signal);
      event="invalid_profile_or_signal_configuration";
      signal.reason=event;
      BVEndSetup(state);
      return false;
     }
   if(previous.time>=bar.time || !BVSignalOHLCValid(previous) || !BVSignalOHLCValid(bar))
     {
      BVSetupSnapshot(state,signal);
      event="invalid_or_nonchronological_signal_OHLC";
      signal.reason=event;
      BVEndSetup(state);
      return false;
     }
   const double volume=BVBarVolume(bar,profile.source);
   if(volume<=0.0 || !MathIsValidNumber(volume))
     {
      BVSetupSnapshot(state,signal);
      event="selected_signal_volume_missing_or_zero";
      signal.reason=event;
      BVEndSetup(state);
      return false;
     }
   const bool is_long=(state.direction==1);
   if(!state.active)
     {
      const bool crossing=(is_long ? previous.close>=profile.val && bar.close<profile.val :
                                    previous.close<=profile.vah && bar.close>profile.vah);
      if(!crossing) return false;
      state.active=true;
      state.weakened=false;
      state.bars=0;
      state.breakout_time=bar.time;
      state.breakout_volume=volume;
      state.extreme=(is_long ? bar.low : bar.high);
      BVSetupSnapshot(state,signal);
      event="breakout";
      signal.reason=event;
      return false; // Breakout bar can never count as weakening.
     }

   state.bars++;
   state.extreme=(is_long ? MathMin(state.extreme,bar.low) : MathMax(state.extreme,bar.high));
   BVSetupSnapshot(state,signal);
   if(state.bars>max_bars)
     {
      event="reclaim_deadline_expired";
      signal.reason=event;
      BVEndSetup(state);
      return false;
     }
   const bool inside=(bar.close>profile.val && bar.close<profile.vah);
   const bool directional=(is_long ? bar.close>bar.open : bar.close<bar.open);
   const bool previous_opposite=(is_long ? previous.close<previous.open : previous.close>previous.open);
   const bool body_engulf=(is_long ? bar.open<=previous.close && bar.close>=previous.open :
                                    bar.open>=previous.close && bar.close<=previous.open);
   signal.engulfing=directional && previous_opposite && body_engulf;
   const bool reached_value=(is_long ? bar.close>=profile.val : bar.close<=profile.vah);
   if(reached_value)
     {
      signal.reclaim_time=bar.time;
      signal.entry_due=bar.time+timeframe_seconds;
      signal.reclaim_volume=volume;
      if(inside && directional && previous_opposite && (!require_engulf || body_engulf) &&
         volume>state.breakout_volume && state.weakened)
        {
         signal.valid=true;
         event="confirmed";
         signal.reason=event;
         BVEndSetup(state);
         return true;
        }
      // A boundary-touch close also ends the excursion. It cannot confirm
      // because a valid reclaim must close strictly between the boundaries.
      if(is_long ? bar.close>=profile.vah : bar.close<=profile.val)
         event="opposite_value_boundary_reached";
      else if(!state.weakened) event="unconfirmed_reentry_no_prior_weakening";
      else if(!directional) event="unconfirmed_reentry_wrong_candle_direction";
      else if(!previous_opposite) event="unconfirmed_reentry_previous_candle_direction";
      else if(require_engulf && !body_engulf) event="unconfirmed_reentry_no_body_engulf";
      else if(volume<=state.breakout_volume) event="unconfirmed_reentry_volume_not_greater";
      else event="unconfirmed_boundary_touch";
      signal.reason=event;
      BVEndSetup(state);
      return false;
     }
   const bool weakening_candle=(is_long ? bar.close<bar.open : bar.close>bar.open);
   if(weakening_candle && volume<state.breakout_volume)
     {
      const bool newly_weakened=!state.weakened;
      state.weakened=true;
      signal.weakening=true;
      event=(newly_weakened ? "weakening" : "outside_value");
     }
   else event="outside_value";
   signal.reason=event;
   return false;
  }
#endif
