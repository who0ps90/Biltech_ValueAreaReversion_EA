# Independent calendar-model verification; this does NOT compile or execute MQL.
# Run in PowerShell on Windows: .\Tests\VerifyTimeMapping.ps1
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
public static class BVTimeCalendarOracle {
    static int Sunday(int year, int month, int ordinal) {
        return 1 + (7 - (int)new DateTime(year,month,1).DayOfWeek)%7 + 7*(ordinal-1);
    }
    static DateTime U(int y,int m,int d,int h) {
        return new DateTime(y,m,d,h,0,0,DateTimeKind.Utc);
    }
    static int NyOffset(DateTime t) {
        DateTime start=U(t.Year,3,Sunday(t.Year,3,2),7);
        DateTime end=U(t.Year,11,Sunday(t.Year,11,1),6);
        return t>=start && t<end ? -240 : -300;
    }
    static int EuOffset(DateTime t) {
        int march=31-(int)new DateTime(t.Year,3,31).DayOfWeek;
        int october=31-(int)new DateTime(t.Year,10,31).DayOfWeek;
        return t>=U(t.Year,3,march,1) && t<U(t.Year,10,october,1) ? 180 : 120;
    }
    static int UsBrokerOffset(DateTime t) { return NyOffset(t)==-240 ? 180 : 120; }
    static int Candidates(DateTime civil,Func<DateTime,int> offset,int winter,int summer) {
        int count=0;
        if(offset(civil.AddMinutes(-winter))==winter) count++;
        if(offset(civil.AddMinutes(-summer))==summer) count++;
        return count;
    }
    static void Check(bool condition,string message) {
        if(!condition) throw new Exception(message);
    }
    public static string Run() {
        TimeZoneInfo ny=TimeZoneInfo.FindSystemTimeZoneById("Eastern Standard Time");
        TimeZoneInfo eu=TimeZoneInfo.FindSystemTimeZoneById("FLE Standard Time");
        int nyChecks=0,euChecks=0,candidateChecks=0,sessionChecks=0;
        for(DateTime t=U(2007,1,1,0); t<U(2100,1,1,0); t=t.AddHours(1)) {
            Check(NyOffset(t)==(int)ny.GetUtcOffset(t).TotalMinutes,"NY UTC offset mismatch at "+t.ToString("o")); nyChecks++;
            Check(EuOffset(t)==(int)eu.GetUtcOffset(t).TotalMinutes,"EU UTC offset mismatch at "+t.ToString("o")); euChecks++;
        }
        for(int y=2007;y<=2099;y++) {
            DateTime spring=U(y,3,Sunday(y,3,2),7);
            DateTime autumn=U(y,11,Sunday(y,11,1),6);
            int lastMarch=31-(int)new DateTime(y,3,31).DayOfWeek;
            int lastOctober=31-(int)new DateTime(y,10,31).DayOfWeek;
            DateTime[] transitions={spring,autumn,U(y,3,lastMarch,1),U(y,10,lastOctober,1)};
            for(int kind=0;kind<transitions.Length;kind++) {
                bool european=kind>=2;
                Func<DateTime,int> offset=european ? (Func<DateTime,int>)EuOffset : UsBrokerOffset;
                // The omitted spring hour and repeated autumn hour begin at
                // UTC transition + winter broker offset, for a +60min change.
                DateTime hour=transitions[kind].AddMinutes(120);
                for(int minute=0;minute<60;minute++) {
                    DateTime civil=hour.AddMinutes(minute);
                    int expected=(kind%2)==0 ? 0 : 2;
                    Check(Candidates(civil,offset,120,180)==expected,"Broker gap/fold mismatch at "+civil.ToString("o")); candidateChecks++;
                }
                DateTime before=hour.AddSeconds(-1),after=hour.AddHours(1);
                Check(Candidates(before,offset,120,180)==1,"Before transition civil hour must be unique"); candidateChecks++;
                Check(Candidates(after,offset,120,180)==1,"After transition civil hour must be unique"); candidateChecks++;
            }
            // Both NY transition days lie within an 18:00-to-18:00 session.
            foreach(DateTime change in new DateTime[]{spring,autumn}) {
                DateTime localDay=DateTime.SpecifyKind(change.Date,DateTimeKind.Unspecified);
                DateTime localStart=localDay.AddDays(-1).AddHours(18),localEnd=localDay.AddHours(18);
                DateTime start=TimeZoneInfo.ConvertTimeToUtc(localStart,ny),end=TimeZoneInfo.ConvertTimeToUtc(localEnd,ny);
                Check((end-start).TotalHours==(change==spring ? 23 : 25),"NY session duration mismatch"); sessionChecks++;
                Check(Candidates(localStart,NyOffset,-300,-240)==1 && Candidates(localEnd,NyOffset,-300,-240)==1,"NY boundary must map uniquely"); sessionChecks++;
            }
        }
        return String.Format("PASS: {0} NY hourly offsets, {1} EU hourly offsets, {2} broker gap/fold checks, {3} NY session checks (2007-2099). Calendar-model tests only; MQL compilation/runtime not exercised.",nyChecks,euChecks,candidateChecks,sessionChecks);
    }
}
'@
[BVTimeCalendarOracle]::Run()
