#ifndef BV_JOURNAL_TESTS_MQH
#define BV_JOURNAL_TESTS_MQH
#include "../Include/BVJournal.mqh"

void BVJournalCheck(const bool passed,const string label,int &failures,int &checks)
  {
   checks++;
   if(passed) return;
   failures++;
   Print("JOURNAL TEST FAILED: ",label);
  }

void BVJournalKeySetTests(int &failures,int &checks)
  {
   BVKeySet keys;
   BVJournalCheck(!keys.Has("missing"),"empty hash set rejects absent key",failures,checks);
   keys.Add("one"); keys.Add("one");
   BVJournalCheck(keys.Has("one") && !keys.Has("ones"),"duplicate adds preserve exact membership",failures,checks);
   for(int i=0;i<2048;i++) keys.Add("growth_"+IntegerToString(i));
   for(int i=0;i<2048;i+=7) keys.Add("growth_"+IntegerToString(i));
   bool preserved=keys.Has("one");
   for(int i=0;i<2048;i++)
      if(!keys.Has("growth_"+IntegerToString(i))) preserved=false;
   BVJournalCheck(preserved,"all keys survive repeated hash-table growth",failures,checks);
   BVJournalCheck(!keys.Has("growth_2048") && !keys.Has("growth_-1"),"grown set rejects nearby absent keys",failures,checks);
   keys.Add("comma,key"); keys.Add("quote\"key");
   BVJournalCheck(keys.Has("comma,key") && keys.Has("quote\"key"),"hash keys preserve punctuation",failures,checks);
  }

void BVJournalCSVTests(int &failures,int &checks)
  {
   string id="",line="";
   BVCSVAdd(line,"event,\"quoted\""); BVCSVAdd(line,"comma,value"); BVCSVAdd(line,"a \"quote\" inside");
   BVJournalCheck(BVParseCSVRow(line,3,id) && id=="event,\"quoted\"","writer/parser roundtrip commas and escaped quotes",failures,checks);
   BVJournalCheck(BVParseCSVRow("\"id\",\"\"",2,id) && id=="id","empty non-ID field is valid",failures,checks);
   BVJournalCheck(!BVParseCSVRow("\"\",\"value\"",2,id),"empty event ID rejected",failures,checks);
   BVJournalCheck(!BVParseCSVRow("",1,id),"empty row rejected",failures,checks);
   BVJournalCheck(!BVParseCSVRow("id,value",2,id),"unquoted row rejected",failures,checks);
   BVJournalCheck(!BVParseCSVRow("\"id\",\"value",2,id),"torn quoted field rejected",failures,checks);
   BVJournalCheck(!BVParseCSVRow("\"id\",\"value\",",2,id),"trailing delimiter rejected",failures,checks);
   BVJournalCheck(!BVParseCSVRow("\"id\"x",1,id),"trailing garbage rejected",failures,checks);
   BVJournalCheck(!BVParseCSVRow("\"id\" \"value\"",2,id),"missing comma rejected",failures,checks);
   BVJournalCheck(!BVParseCSVRow("\"id\",\"value\"",3,id),"too few columns rejected",failures,checks);
   BVJournalCheck(!BVParseCSVRow("\"id\",\"value\"",1,id),"too many columns rejected",failures,checks);
   BVJournalCheck(!BVParseCSVRow("\"id\"",0,id),"zero expected columns rejected",failures,checks);
   string clean=BVCSVCell("one\r\ntwo\tthree");
   BVJournalCheck(StringFind(clean,"\r")<0 && StringFind(clean,"\n")<0 && StringFind(clean,"\t")<0,
                  "CSV writer sanitizes multiline and journal delimiters",failures,checks);
  }

// Files are created only in the Strategy Tester's MQL5/Files sandbox. The
// unique BV_SELFTEST_JOURNAL prefix belongs exclusively to this fixture.
void BVJournalFileTests(int &failures,int &checks)
  {
   string suffix=StringFormat("%I64u_%I64u",GetTickCount64(),GetMicrosecondCount());
   string path="BV_SELFTEST_JOURNAL_"+suffix+".tsv";
   string future_path="BV_SELFTEST_JOURNAL_FUTURE_"+suffix+".tsv";
   string torn_path="BV_SELFTEST_JOURNAL_TORN_"+suffix+".tsv";
   string extra_path="BV_SELFTEST_JOURNAL_EXTRA_"+suffix+".tsv";
   string reason="";
   datetime now=TimeCurrent();
   BVJournal journal;
   bool opened=journal.Open(path,now,reason);
   BVJournalCheck(opened,"new tester-sandbox journal opens",failures,checks);
   if(opened)
     {
      BVJournalCheck(journal.Count()==0,"new journal has zero rows",failures,checks);
      BVJournalCheck(!journal.Put("","key","value") && !journal.Put("STATE","","value"),
                     "empty kind/key cannot create unreadable journal rows",failures,checks);
      BVJournalCheck(!journal.Put("STATE","bad-tab","one\ttwo") &&
                     !journal.Put("STATE","bad-line","one\ntwo") && !journal.Put("STATE","bad-cr","one\rtwo"),
                     "raw journal delimiters rejected",failures,checks);
      string config="symbol=TEST,source=CFD|file=events,manual.csv|quote=\"value\"";
      BVJournalCheck(journal.Put("CONFIG","identity",config),"comma-bearing configuration persists in tab journal",failures,checks);
      BVJournalRow row;
      BVJournalCheck(journal.Find("CONFIG","identity",row) && row.a==config,
                     "configuration reads intact before reopening",failures,checks);
      BVJournalCheck(journal.Put("STATE","latest","first","0") && journal.Put("STATE","latest","second","1"),
                     "successive updates append successfully",failures,checks);
      BVJournalCheck(journal.Find("STATE","latest",row) && row.a=="second" && row.b=="1",
                     "lookup returns latest matching key",failures,checks);
      string payload="";
      BVCSVAdd(payload,"outbox_event,1"); BVCSVAdd(payload,"comma and \"quoted\" payload");
      BVJournalCheck(journal.Put("OUTBOX_SIGNAL","outbox_event,1",payload),"CSV payload enters durable outbox",failures,checks);
      bool all_written=true;
      for(int i=0;i<600;i++) if(!journal.Put("GROWTH",IntegerToString(i),"row_"+IntegerToString(i))) all_written=false;
      BVJournalCheck(all_written,"journal appends across hash-index growth",failures,checks);
      bool all_found=true;
      for(int i=0;i<600;i++)
         if(!journal.Find("GROWTH",IntegerToString(i),row) || row.a!="row_"+IntegerToString(i)) all_found=false;
      BVJournalCheck(all_found,"journal hash-index growth preserves every row",failures,checks);
      int expected=journal.Count();
      BVJournalCheck(expected==604,"invalid writes do not append journal rows",failures,checks);
      BVJournalCheck(journal.Row(0,row) && row.kind=="CONFIG" && row.key=="identity" && row.a==config,
                     "ordered row enumeration preserves original record",failures,checks);
      BVJournalCheck(!journal.Row(-1,row) && !journal.Row(expected,row),"row bounds checked",failures,checks);
      journal.Close();
      BVJournalCheck(!journal.Put("STATE","closed","value"),"writes to closed journal fail",failures,checks);
      opened=journal.Open(path,now,reason);
      BVJournalCheck(opened && journal.Count()==expected,"same-object reopen reloads without duplicate in-memory rows",failures,checks);
      if(opened)
        {
         BVJournalCheck(journal.Find("CONFIG","identity",row) && row.a==config,
                        "comma-bearing configuration survives disk reload",failures,checks);
         BVJournalCheck(journal.Find("OUTBOX_SIGNAL","outbox_event,1",row) && row.a==payload,
                        "outbox payload survives disk reload exactly",failures,checks);
         BVJournalCheck(journal.Find("STATE","latest",row) && row.a=="second" && row.b=="1",
                        "latest key update survives disk reload",failures,checks);
         BVJournalCheck(!journal.Has("STATE","absent"),"reloaded index rejects absent key",failures,checks);
         opened=journal.Open(path,now,reason);
         BVJournalCheck(opened && journal.Count()==expected,"Open closes prior handle and resets index before reuse",failures,checks);
        }
     }
   journal.Close();
   BVJournalCheck(!FileIsExist(path) || FileDelete(path),"selftest journal cleanup remains in tester sandbox",failures,checks);
   // An explicit future timestamp tests refusal to reuse an independent run's
   // journal. This fixture does not alter terminal time or trading state.
   int handle=FileOpen(future_path,FILE_WRITE|FILE_CSV|FILE_ANSI,'\t',CP_UTF8);
   bool created=handle!=INVALID_HANDLE;
   if(created) { created=FileWrite(handle,"STATE",(long)(now+3600),"future","value","","")>0; FileClose(handle); }
   BVJournalCheck(created,"future-dated test journal created",failures,checks);
   if(created)
     {
      BVJournal future;
      BVJournalCheck(!future.Open(future_path,now,reason) && StringFind(reason,"ahead")>=0,
                     "future journal refuses reuse with actionable reason",failures,checks);
      future.Close();
     }
   BVJournalCheck(!FileIsExist(future_path) || FileDelete(future_path),"future fixture cleanup remains in tester sandbox",failures,checks);
   // A valid kind/time/key must not hide a truncated tail or an extra field.
   // Raw text avoids the normal writer's validation, modeling torn/corrupt IO.
   handle=FileOpen(torn_path,FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   created=handle!=INVALID_HANDLE;
   if(created)
     {
      created=FileWriteString(handle,"STATE\t"+IntegerToString((long)now)+"\ttorn-key\tvalue\r\n")>0;
      FileClose(handle);
     }
   BVJournalCheck(created,"torn journal with valid identifying fields created",failures,checks);
   if(created)
     {
      BVJournal torn;
      BVJournalCheck(!torn.Open(torn_path,now,reason),"torn journal missing final two columns is refused",failures,checks);
      torn.Close();
     }
   BVJournalCheck(!FileIsExist(torn_path) || FileDelete(torn_path),"torn fixture cleanup remains in tester sandbox",failures,checks);
   handle=FileOpen(extra_path,FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   created=handle!=INVALID_HANDLE;
   if(created)
     {
      created=FileWriteString(handle,"STATE\t"+IntegerToString((long)now)+"\textra-key\tvalue\t\t\tunexpected\r\n")>0;
      FileClose(handle);
     }
   BVJournalCheck(created,"journal with unexpected seventh field created",failures,checks);
   if(created)
     {
      BVJournal extra;
      BVJournalCheck(!extra.Open(extra_path,now,reason),"journal with seventh column is refused",failures,checks);
      extra.Close();
     }
   BVJournalCheck(!FileIsExist(extra_path) || FileDelete(extra_path),"extra-field fixture cleanup remains in tester sandbox",failures,checks);
  }

int BVRunJournalTests()
  {
   // Guard even if this include is invoked from a different runner later.
   if(!MQLInfoInteger(MQL_TESTER)) { Print("Journal fixtures require Strategy Tester; no files touched."); return 1; }
   int failures=0,checks=0;
   BVJournalKeySetTests(failures,checks);
   BVJournalCSVTests(failures,checks);
   BVJournalFileTests(failures,checks);
   PrintFormat("Journal self-tests: %d checks, %d failures.",checks,failures);
   return failures;
  }
#endif
