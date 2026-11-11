#ifndef BV_TIME_MQH
#define BV_TIME_MQH
#include "BVTypes.mqh"

// All civil datetimes in this module are calendar labels, not terminal-local time.
// Supported converted calendar years: 2007 through 2099 inclusive.
// FIXED: winter_minutes applies throughout the year; summer_minutes is unused.
// EU: transitions at 01:00 UTC on the last Sunday of March and October.
// US: follows New York transition INSTANTS (07:00 UTC in March, 06:00 UTC
// in November), not 02:00 on the configured broker's clock.
// Seasonal feeds lose information in their repeated autumn clock hour. The
// reverse conversion rejects that entire ambiguous civil hour. Callers must
// preflight loaded history and reject affected sessions; never guess a fold.
class BVClock
  {
private:
   BVTimeConfig m_cfg;
   bool m_ready;

   bool Ready(string &reason)
     {
      if(m_ready) return true;
      reason="Time mapping has not been initialized. Configure the historical broker UTC offset explicitly.";
      return false;
     }

   bool Parts(const datetime value,MqlDateTime &parts)
     {
      if(!TimeToStruct(value,parts)) return false;
      return parts.year>=2007 && parts.year<=2099;
     }

   datetime Civil(const int year,const int month,const int day,const int hour=0)
     {
      MqlDateTime parts;
      ZeroMemory(parts);
      parts.year=year; parts.mon=month; parts.day=day; parts.hour=hour;
      return StructToTime(parts);
     }

   int Sunday(const int year,const int month,const int ordinal)
     {
      MqlDateTime first;
      TimeToStruct(Civil(year,month,1),first);
      return 1+(7-first.day_of_week)%7+7*(ordinal-1);
     }

   int LastSunday(const int year,const int month)
     {
      // Both EU transition months have 31 days.
      MqlDateTime last;
      TimeToStruct(Civil(year,month,31),last);
      return 31-last.day_of_week;
     }

   int NewYorkOffset(const datetime utc)
     {
      MqlDateTime parts;
      if(!Parts(utc,parts)) return 0;
      datetime begin=Civil(parts.year,3,Sunday(parts.year,3,2),7);
      datetime end=Civil(parts.year,11,Sunday(parts.year,11,1),6);
      return utc>=begin && utc<end ? -240 : -300;
     }

   bool BrokerOffset(const datetime utc,int &minutes,string &reason)
     {
      MqlDateTime parts;
      if(!Parts(utc,parts))
        {
         reason="UTC date is outside the supported 2007-2099 calendar range.";
         return false;
        }
      minutes=m_cfg.winter_minutes;
      if(m_cfg.broker_rule==BV_OFFSET_FIXED) return true;
      datetime begin,end;
      if(m_cfg.broker_rule==BV_OFFSET_EU)
        {
         begin=Civil(parts.year,3,LastSunday(parts.year,3),1);
         end=Civil(parts.year,10,LastSunday(parts.year,10),1);
        }
      else
        {
         begin=Civil(parts.year,3,Sunday(parts.year,3,2),7);
         end=Civil(parts.year,11,Sunday(parts.year,11,1),6);
        }
      if(utc>=begin && utc<end) minutes=m_cfg.summer_minutes;
      return true;
     }

   string DateId(const datetime civil)
     {
      MqlDateTime parts;
      TimeToStruct(civil,parts);
      return StringFormat("%04d-%02d-%02d",parts.year,parts.mon,parts.day);
     }

   datetime Midnight(const datetime civil)
     {
      MqlDateTime parts;
      TimeToStruct(civil,parts);
      parts.hour=0; parts.min=0; parts.sec=0;
      return StructToTime(parts);
     }

public:
   BVClock(void) { m_ready=false; }

   bool Init(const BVTimeConfig &cfg,string &reason)
     {
      m_ready=false;
      reason="";
      if(cfg.mode!=BV_NEW_YORK_SESSION && cfg.mode!=BV_BROKER_CUSTOM_SESSION)
        { reason="Unknown profile session mode."; return false; }
      if(cfg.broker_rule!=BV_OFFSET_FIXED && cfg.broker_rule!=BV_OFFSET_EU && cfg.broker_rule!=BV_OFFSET_US)
        {
         reason="Historical broker UTC mapping is unconfigured. Select FIXED, EU or US and enter verified winter/summer offsets in minutes; the terminal's current offset is never inferred.";
         return false;
        }
      if(cfg.winter_minutes < -840 || cfg.winter_minutes > 840)
        { reason="Broker winter/fixed UTC offset must be between -840 and +840 minutes."; return false; }
      if(cfg.broker_rule!=BV_OFFSET_FIXED &&
         (cfg.summer_minutes < -840 || cfg.summer_minutes > 840 || cfg.summer_minutes!=cfg.winter_minutes+60))
        {
         reason="EU/US seasonal mapping requires summer offset = winter offset + 60 minutes, both within -840 to +840 minutes. Use verified historical broker rules.";
         return false;
        }
      if(cfg.custom_boundary_minutes<0 || cfg.custom_boundary_minutes>=1440)
        { reason="Custom broker session boundary must be 0-1439 minutes after broker midnight."; return false; }
      m_cfg=cfg;
      m_ready=true;
      return true;
     }

   bool UTCToBroker(const datetime utc,datetime &broker,string &reason)
     {
      reason=""; broker=0;
      if(!Ready(reason)) return false;
      int minutes=0;
      if(!BrokerOffset(utc,minutes,reason)) return false;
      datetime candidate=(datetime)((long)utc+(long)minutes*60);
      MqlDateTime parts;
      if(!Parts(candidate,parts))
        { reason="Converted broker date is outside the supported 2007-2099 calendar range."; return false; }
      broker=candidate;
      return true;
     }

   bool BrokerToUTC(const datetime broker,datetime &utc,string &reason)
     {
      reason=""; utc=0;
      if(!Ready(reason)) return false;
      MqlDateTime parts;
      if(!Parts(broker,parts))
        { reason="Broker date is outside the supported 2007-2099 calendar range."; return false; }
      datetime accepted=0;
      int matches=0;
      int count=m_cfg.broker_rule==BV_OFFSET_FIXED ? 1 : 2;
      for(int i=0;i<count;i++)
        {
         int assumed=i==0 ? m_cfg.winter_minutes : m_cfg.summer_minutes;
         datetime candidate=(datetime)((long)broker-(long)assumed*60);
         int actual=0;
         string detail="";
         if(BrokerOffset(candidate,actual,detail) && actual==assumed)
           { accepted=candidate; matches++; }
        }
      if(matches==1) { utc=accepted; return true; }
      if(matches>1)
        reason="Ambiguous historical broker timestamp "+BVStamp(broker)+": repeated autumn DST hour has two UTC matches. Use a verified fixed-offset/UTC-stamped feed or exclude this session; do not guess the fold.";
      else
        reason="Unmappable historical broker timestamp "+BVStamp(broker)+": nonexistent spring DST hour or supported-year boundary. Verify the configured rule/offsets; use a verified fixed-offset/UTC-stamped feed or exclude this session.";
      return false;
     }

   datetime UTCToNY(const datetime utc)
     {
      if(!m_ready) return 0;
      int minutes=NewYorkOffset(utc);
      if(minutes==0) return 0;
      datetime ny=(datetime)((long)utc+(long)minutes*60);
      MqlDateTime parts;
      return Parts(ny,parts) ? ny : 0;
     }

   bool NYToUTC(const datetime ny,datetime &utc,string &reason)
     {
      reason=""; utc=0;
      if(!Ready(reason)) return false;
      MqlDateTime parts;
      if(!Parts(ny,parts))
        { reason="New York date is outside the supported 2007-2099 calendar range."; return false; }
      datetime accepted=0;
      int matches=0;
      for(int i=0;i<2;i++)
        {
         int assumed=i==0 ? -300 : -240;
         datetime candidate=(datetime)((long)ny-(long)assumed*60);
         if(NewYorkOffset(candidate)==assumed)
           { accepted=candidate; matches++; }
        }
      if(matches==1) { utc=accepted; return true; }
      reason=matches>1 ? "Ambiguous New York civil time in the repeated autumn 01:00 hour; supply UTC instead."
                       : "Nonexistent New York civil time in the spring 02:00 hour, or supported-year boundary; supply a valid UTC time.";
      return false;
     }

   bool SessionAtUTC(const datetime utc,BVSession &session,string &reason)
     {
      reason="";
      session.id=""; session.start_utc=0; session.end_utc=0;
      session.start_broker=0; session.end_broker=0;
      if(!Ready(reason)) return false;
      datetime local=0;
      if(m_cfg.mode==BV_NEW_YORK_SESSION)
        {
         local=UTCToNY(utc);
         if(local==0) { reason="Cannot determine New York profile session outside supported 2007-2099 dates."; return false; }
        }
      else if(!UTCToBroker(utc,local,reason)) return false;
      int boundary=m_cfg.mode==BV_NEW_YORK_SESSION ? 18*60 : m_cfg.custom_boundary_minutes;
      datetime begin=(datetime)((long)Midnight(local)+(long)boundary*60);
      if(local<begin) begin=(datetime)((long)begin-86400);
      datetime end=(datetime)((long)begin+86400);
      datetime begin_utc=0,end_utc=0;
      if(m_cfg.mode==BV_NEW_YORK_SESSION)
        {
         if(!NYToUTC(begin,begin_utc,reason) || !NYToUTC(end,end_utc,reason)) return false;
        }
      else
        {
         if(!BrokerToUTC(begin,begin_utc,reason) || !BrokerToUTC(end,end_utc,reason))
           { reason="Custom broker session boundary cannot be mapped: "+reason; return false; }
        }
      if(begin_utc>utc || utc>=end_utc || end_utc<=begin_utc)
        { reason="Time mapping produced inconsistent profile session bounds; verify the broker rule."; return false; }
      datetime begin_broker=0,end_broker=0;
      if(!UTCToBroker(begin_utc,begin_broker,reason) || !UTCToBroker(end_utc,end_broker,reason)) return false;
      session.id=DateId(begin);
      session.start_utc=begin_utc; session.end_utc=end_utc;
      session.start_broker=begin_broker; session.end_broker=end_broker;
      return true;
     }

   bool PreviousSession(const BVSession &current,BVSession &previous,string &reason)
     {
      reason="";
      if(current.start_utc<=0 || current.end_utc<=current.start_utc)
        { reason="Cannot find the previous session from invalid current-session bounds."; return false; }
      if(!SessionAtUTC((datetime)((long)current.start_utc-1),previous,reason)) return false;
      if(previous.end_utc!=current.start_utc)
        { reason="Previous profile session is not contiguous under the configured historical time mapping."; return false; }
      return true;
     }

   bool NYDay(const datetime utc,string &id,datetime &start_utc,string &reason)
     {
      id=""; start_utc=0; reason="";
      if(!Ready(reason)) return false;
      datetime ny=UTCToNY(utc);
      if(ny==0) { reason="Cannot determine New York day outside supported 2007-2099 dates."; return false; }
      datetime midnight=Midnight(ny);
      if(!NYToUTC(midnight,start_utc,reason)) return false;
      id=DateId(midnight);
      return true;
     }

   // Half-open [start,end); overnight windows are supported. Equal endpoints
   // explicitly mean all day. Inputs and forced-exit cutoffs use NY minutes.
   bool InWindow(const datetime utc,const int start_minutes,const int end_minutes)
     {
      if(start_minutes<0 || start_minutes>=1440 || end_minutes<0 || end_minutes>=1440) return false;
      datetime ny=UTCToNY(utc);
      if(ny==0) return false;
      MqlDateTime parts;
      TimeToStruct(ny,parts);
      int now_minutes=parts.hour*60+parts.min;
      if(start_minutes==end_minutes) return true;
      if(start_minutes<end_minutes) return now_minutes>=start_minutes && now_minutes<end_minutes;
      return now_minutes>=start_minutes || now_minutes<end_minutes;
     }

   bool AtOrAfterNY(const datetime utc,const int minutes)
     {
      if(minutes<0 || minutes>=1440) return false;
      datetime ny=UTCToNY(utc);
      if(ny==0) return false;
      MqlDateTime parts;
      TimeToStruct(ny,parts);
      return parts.hour*60+parts.min>=minutes;
     }
  };
#endif
