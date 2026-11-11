#ifndef BV_PROFILE_MQH
#define BV_PROFILE_MQH
#include "BVTypes.mqh"

// All bins are half-open [lower, upper), except the final upper edge. A
// zero-range observation on an interior edge belongs to the higher bin.
// POC is the winning bin midpoint; edges, rather than midpoints, are tick aligned.
bool BVProfileReject(BVProfile &profile,string &reason,const string detail)
  {
   profile.valid=false;
   profile.reason=detail;
   reason=detail;
   return false;
  }

void BVProfileAccumulate(double &sum,double &compensation,const double value)
  {
   const double y=value-compensation;
   const double next=sum+y;
   compensation=(next-sum)-y;
   sum=next;
  }

bool BVBuildProfile(const MqlRates &bars[],const BVSession &session,
                    const BVProfileConfig &cfg,const double tick_size,
                    BVProfile &profile,string &reason)
  {
   ZeroMemory(profile);
   profile.session=session;
   reason="";
   const int count=ArraySize(bars);
   profile.bar_count=count;
   if(session.start_broker<=0 || session.end_broker<=session.start_broker)
      return BVProfileReject(profile,reason,"invalid_profile_session_boundaries");
   if(!MathIsValidNumber(tick_size) || tick_size<=0.0)
      return BVProfileReject(profile,reason,"invalid_symbol_tick_size");
   if(cfg.rows<1 || cfg.rows>100000 || cfg.min_bars<1 ||
      cfg.max_gap_minutes<0 || cfg.max_edge_gap_minutes<0 ||
      !MathIsValidNumber(cfg.value_fraction) || cfg.value_fraction<=0.0 || cfg.value_fraction>1.0)
      return BVProfileReject(profile,reason,"invalid_profile_configuration");
   if(count==0)
      return BVProfileReject(profile,reason,"empty_previous_session");
   if(count<cfg.min_bars)
      return BVProfileReject(profile,reason,"insufficient_previous_session_M1_bars");

   double low=bars[0].low,high=bars[0].high;
   bool all_real=true,all_tick=true;
   for(int i=0;i<count;i++)
     {
      if((long)bars[i].time%60!=0 || bars[i].time<session.start_broker || bars[i].time+60>session.end_broker)
         return BVProfileReject(profile,reason,"M1_bar_outside_completed_previous_session");
      if(i>0)
        {
         if(bars[i].time<=bars[i-1].time)
            return BVProfileReject(profile,reason,"M1_history_not_strictly_chronological");
         // max_gap_minutes is the number of absent M1 minutes, excluding
         // the preceding available minute itself.
         if((long)(bars[i].time-bars[i-1].time-60)>(long)cfg.max_gap_minutes*60)
            return BVProfileReject(profile,reason,"excessive_internal_M1_history_gap");
        }
      if(!MathIsValidNumber(bars[i].open) || !MathIsValidNumber(bars[i].close) ||
         !MathIsValidNumber(bars[i].low) || !MathIsValidNumber(bars[i].high) ||
         bars[i].high<bars[i].low || bars[i].open<bars[i].low ||
         bars[i].open>bars[i].high || bars[i].close<bars[i].low || bars[i].close>bars[i].high)
         return BVProfileReject(profile,reason,"invalid_M1_OHLC");
      low=MathMin(low,bars[i].low);
      high=MathMax(high,bars[i].high);
      if(bars[i].real_volume<=0) all_real=false;
      if(bars[i].tick_volume<=0) all_tick=false;
     }
   if((long)(bars[0].time-session.start_broker)>(long)cfg.max_edge_gap_minutes*60 ||
      (long)(session.end_broker-(bars[count-1].time+60))>(long)cfg.max_edge_gap_minutes*60)
      return BVProfileReject(profile,reason,"excessive_session_edge_M1_history_gap");

   if(cfg.volume_mode==BV_AUTO)
     {
      if(all_real)
        {
         profile.source=BV_REAL_VOLUME;
         profile.source_note="AUTO selected positive real volume for every profile M1 bar";
        }
      else if(all_tick)
        {
         profile.source=BV_TICK_VOLUME;
         profile.source_note="WARNING: AUTO fell back to tick volume; at least one profile M1 bar lacked positive real volume";
        }
      else return BVProfileReject(profile,reason,"AUTO_has_no_consistently_positive_session_volume_source");
     }
   else if(cfg.volume_mode==BV_REAL_VOLUME)
     {
      profile.source=BV_REAL_VOLUME;
      if(!all_real) return BVProfileReject(profile,reason,"required_real_volume_missing_or_zero_in_profile");
      profile.source_note="Explicit real volume";
     }
   else if(cfg.volume_mode==BV_TICK_VOLUME)
     {
      profile.source=BV_TICK_VOLUME;
      if(!all_tick) return BVProfileReject(profile,reason,"required_tick_volume_missing_or_zero_in_profile");
      profile.source_note="Explicit tick volume (quote activity, not centralized exchange volume)";
     }
   else return BVProfileReject(profile,reason,"unknown_volume_mode");

   // Small tick-coordinate tolerances remove representation noise at an
   // exact tick edge. Width is an integer number of ticks and rows <= request.
   const double edge_epsilon=1.0e-9;
   const double origin_ticks=MathFloor(low/tick_size+edge_epsilon);
   const double origin=origin_ticks*tick_size;
   double span_ticks=MathCeil((high-origin)/tick_size-edge_epsilon);
   if(!MathIsValidNumber(origin) || !MathIsValidNumber(span_ticks) || span_ticks>9007199254740991.0)
      return BVProfileReject(profile,reason,"profile_price_range_not_representable");
   span_ticks=MathMax(1.0,span_ticks);
   const double width_ticks=MathMax(1.0,MathCeil(span_ticks/(double)cfg.rows));
   const double width=width_ticks*tick_size;
   const int rows=(int)MathCeil(span_ticks/width_ticks);
   if(rows<1 || rows>cfg.rows || !MathIsValidNumber(width) || width<=0.0)
      return BVProfileReject(profile,reason,"invalid_tick_aligned_profile_bins");
   double histogram[],bin_compensation[];
   if(ArrayResize(histogram,rows)!=rows || ArrayResize(bin_compensation,rows)!=rows)
      return BVProfileReject(profile,reason,"profile_histogram_allocation_failed");
   ArrayInitialize(histogram,0.0);
   ArrayInitialize(bin_compensation,0.0);
   double total=0.0,compensation=0.0;
   for(int i=0;i<count;i++)
     {
      const double volume=BVBarVolume(bars[i],profile.source);
      BVProfileAccumulate(total,compensation,volume);
      if(!MathIsValidNumber(total) || total<=0.0)
         return BVProfileReject(profile,reason,"invalid_or_overflowing_profile_volume");
      if(bars[i].high==bars[i].low)
        {
         int index=(int)MathFloor((bars[i].close-origin)/width+edge_epsilon);
         index=MathMax(0,MathMin(rows-1,index));
         BVProfileAccumulate(histogram[index],bin_compensation[index],volume);
         continue;
        }
      int first=(int)MathFloor((bars[i].low-origin)/width+edge_epsilon);
      int last=(int)MathCeil((bars[i].high-origin)/width-edge_epsilon)-1;
      first=MathMax(0,MathMin(rows-1,first));
      last=MathMax(first,MathMin(rows-1,last));
      const double range=bars[i].high-bars[i].low;
      double remaining=volume;
      for(int bin=first;bin<=last;bin++)
        {
         const double lower=origin+(double)bin*width;
         const double upper=origin+(double)(bin+1)*width;
         const double overlap=MathMax(0.0,MathMin(bars[i].high,upper)-MathMax(bars[i].low,lower));
         // Put each bar's floating-point residual into its final overlapping
         // bin so every input observation conserves its full selected volume.
         double allocation=(bin==last ? remaining : volume*(overlap/range));
         if(allocation<0.0 && allocation>-volume*1.0e-12) allocation=0.0;
         if(!MathIsValidNumber(allocation) || allocation<0.0)
            return BVProfileReject(profile,reason,"negative_or_invalid_histogram_allocation");
         BVProfileAccumulate(histogram[bin],bin_compensation[bin],allocation);
         remaining-=allocation;
        }
     }
   double allocated=0.0,allocated_compensation=0.0;
   for(int i=0;i<rows;i++) BVProfileAccumulate(allocated,allocated_compensation,histogram[i]);
   const double tolerance=MathMax(1.0e-7,total*1.0e-10);
   if(!MathIsValidNumber(allocated) || MathAbs(total-allocated)>tolerance)
      return BVProfileReject(profile,reason,"profile_volume_conservation_failed");
   // 32 double-precision ulps at session-volume scale distinguish mathematical
   // ties from allocation/summation noise (e.g. three identical range overlaps).
   // Do not move a global summation residual into a price bin: it can bias POC.
   const double tie_epsilon=total*7.105427357601002e-15;
   int poc=0;
   for(int i=1;i<rows;i++)
      if(histogram[i]>histogram[poc]+tie_epsilon) poc=i; // Ties retain the lower bin.
   int left=poc,right=poc;
   double included=histogram[poc];
   const double target=total*cfg.value_fraction;
   while(included+tie_epsilon<target && (left>0 || right<rows-1))
     {
      const bool can_left=(left>0),can_right=(right<rows-1);
      if(can_left && (!can_right || histogram[left-1]+tie_epsilon>=histogram[right+1]))
        { left--; included+=histogram[left]; } // Adjacent ties expand lower first.
      else
        { right++; included+=histogram[right]; }
     }
   profile.rows=rows;
   profile.bin_width=width;
   profile.bin_origin=origin;
   profile.val=origin+(double)left*width;
   profile.vah=origin+(double)(right+1)*width;
   profile.poc=origin+((double)poc+0.5)*width;
   profile.total_volume=total;
   profile.allocated_volume=allocated;
   profile.valid=true;
   profile.reason="valid_completed_previous_session_profile";
   reason=profile.reason;
   return true;
  }
#endif
