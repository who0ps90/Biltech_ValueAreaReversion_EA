#ifndef BV_TYPES_MQH
#define BV_TYPES_MQH
enum BVVolumeMode { BV_TICK_VOLUME=0, BV_REAL_VOLUME=1, BV_AUTO=2 };
enum BVSessionMode { BV_NEW_YORK_SESSION=0, BV_BROKER_CUSTOM_SESSION=1 };
enum BVBrokerRule { BV_OFFSET_UNCONFIGURED=0, BV_OFFSET_FIXED=1, BV_OFFSET_EU=2, BV_OFFSET_US=3 };
struct BVTimeConfig
  {
   BVSessionMode mode;
   BVBrokerRule broker_rule;
   int winter_minutes;
   int summer_minutes;
   int custom_boundary_minutes;
  };
struct BVSession
  {
   string id;
   datetime start_utc,end_utc,start_broker,end_broker;
  };
struct BVProfile
  {
   bool valid;
   string reason,source_note;
   BVSession session;
   BVVolumeMode source;
   double val,vah,poc,total_volume,allocated_volume,bin_width,bin_origin;
   int rows,bar_count;
  };
struct BVProfileConfig
  {
   int rows,min_bars,max_gap_minutes,max_edge_gap_minutes;
   double value_fraction;
   BVVolumeMode volume_mode;
  };
struct BVSetup
  {
   bool active,weakened;
   int direction,bars;
   datetime breakout_time,last_bar_time;
   double breakout_volume,extreme;
  };
struct BVSignal
  {
   bool valid,weakening,engulfing;
   int direction,bars;
   datetime breakout_time,reclaim_time,entry_due;
   double breakout_volume,reclaim_volume,extreme,atr,buffer;
   string reason;
  };
struct BVPlan
  {
   double entry,actual_entry,sl,tp,spread_points,rr,risk_budget,volume,initial_risk;
   string reason;
  };
string BVSourceName(const BVVolumeMode source)
  { return source==BV_REAL_VOLUME ? "REAL_VOLUME" : (source==BV_TICK_VOLUME ? "TICK_VOLUME" : "AUTO"); }
double BVBarVolume(const MqlRates &bar,const BVVolumeMode source)
  { return source==BV_REAL_VOLUME ? (double)bar.real_volume : (double)bar.tick_volume; }
string BVStamp(const datetime t) { return t==0 ? "" : TimeToString(t,TIME_DATE|TIME_SECONDS); }
#endif
