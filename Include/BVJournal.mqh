#ifndef BV_JOURNAL_MQH
#define BV_JOURNAL_MQH
// Append-only journal is flushed before an order attempt. Use a new RunId for
// each independent test; same RunId is reserved for deliberate continuation.
struct BVJournalRow { string kind,key,a,b,c; datetime time; };
uint BVKeyHash(const string key)
  { uint hash=2166136261; for(int i=0;i<StringLen(key);i++) { hash^=(uint)StringGetCharacter(key,i); hash*=16777619; } return hash; }
// Open-addressed indexes keep long historical runs from doing a full audit
// scan for every event. Collisions always compare the original complete key.
class BVKeySet
  {
private:
   string m_keys[];
   int m_table[];
   void InsertIndex(const int index)
     {
      int capacity=ArraySize(m_table),slot=(int)(BVKeyHash(m_keys[index])%(uint)capacity);
      while(m_table[slot]!=0) slot=(slot+1)%capacity;
      m_table[slot]=index+1;
     }
   void Grow(void)
     {
      int capacity=ArraySize(m_table); capacity=capacity==0?1024:capacity*2;
      ArrayResize(m_table,capacity); ArrayInitialize(m_table,0);
      for(int i=0;i<ArraySize(m_keys);i++) InsertIndex(i);
     }
public:
   bool Has(const string key)
     {
      int capacity=ArraySize(m_table); if(capacity==0) return false;
      int slot=(int)(BVKeyHash(key)%(uint)capacity);
      while(m_table[slot]!=0) { if(m_keys[m_table[slot]-1]==key) return true; slot=(slot+1)%capacity; }
      return false;
     }
   void Add(const string key)
     {
      if(Has(key)) return;
      if((ArraySize(m_keys)+1)*2>=ArraySize(m_table)) Grow();
      int n=ArraySize(m_keys); ArrayResize(m_keys,n+1); m_keys[n]=key; InsertIndex(n);
     }
  };
class BVJournal
  {
private:
   int m_handle;
   BVJournalRow m_rows[];
   int m_index[];
   void IndexRow(const int index)
     {
      int capacity=ArraySize(m_index);
      string key=m_rows[index].kind+"\t"+m_rows[index].key;
      int slot=(int)(BVKeyHash(key)%(uint)capacity);
      while(m_index[slot]!=0)
        {
         int old=m_index[slot]-1;
         if(m_rows[old].kind==m_rows[index].kind && m_rows[old].key==m_rows[index].key) break;
         slot=(slot+1)%capacity;
        }
      m_index[slot]=index+1;
     }
   void AddRow(const BVJournalRow &row)
     {
      int n=ArraySize(m_rows),capacity=ArraySize(m_index);
      if((n+1)*2>=capacity)
        {
         capacity=capacity==0?1024:capacity*2;
         ArrayResize(m_index,capacity); ArrayInitialize(m_index,0);
         for(int i=0;i<n;i++) IndexRow(i);
        }
      ArrayResize(m_rows,n+1); m_rows[n]=row; IndexRow(n);
     }
public:
   BVJournal(void) { m_handle=INVALID_HANDLE; }
   bool Open(const string path,const datetime now,string &reason)
     {
      Close();
      ArrayResize(m_rows,0); ArrayResize(m_index,0);
      reason="";
      // Journal uses TAB fields so ordinary commas in event/config text remain
      // intact. Public audit CSVs use a separate quoted writer.
      m_handle=FileOpen(path,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
      if(m_handle==INVALID_HANDLE) { reason="Cannot open journal: "+path; return false; }
      datetime latest=0;
      while(!FileIsEnding(m_handle))
        {
         BVJournalRow r;
         string line=FileReadString(m_handle);
         if(line=="" && FileIsEnding(m_handle)) break;
         string fields[6]; int start=0; bool valid=true;
         for(int column=0;column<5;column++)
           {
            int delimiter=StringFind(line,"\t",start);
            if(delimiter<0) { valid=false; break; }
            fields[column]=StringSubstr(line,start,delimiter-start); start=delimiter+1;
           }
         fields[5]=StringSubstr(line,start);
         if(StringFind(fields[5],"\t")>=0) valid=false;
         r.kind=fields[0]; r.time=(datetime)StringToInteger(fields[1]);
         r.key=fields[2]; r.a=fields[3]; r.b=fields[4]; r.c=fields[5];
         if(!valid || r.kind=="" || r.time<=0 || r.key=="" || IntegerToString((long)r.time)!=fields[1])
           { reason="Invalid journal row; preserve evidence and choose a new RunId"; return false; }
         AddRow(r);
         if(r.time>latest) latest=r.time;
        }
      FileSeek(m_handle,0,SEEK_END);
      if(latest>now)
        { reason="Journal is ahead of tester time: use a new RunId for a new backtest"; return false; }
      return true;
     }
   bool Find(const string kind,const string key,BVJournalRow &row)
     {
      int capacity=ArraySize(m_index); if(capacity==0) return false;
      int slot=(int)(BVKeyHash(kind+"\t"+key)%(uint)capacity);
      while(m_index[slot]!=0)
        {
         int index=m_index[slot]-1;
         if(m_rows[index].kind==kind && m_rows[index].key==key) { row=m_rows[index]; return true; }
         slot=(slot+1)%capacity;
        }
      return false;
     }
   bool Has(const string kind,const string key)
     { BVJournalRow r; return Find(kind,key,r); }
   int Count(void) { return ArraySize(m_rows); }
   bool Row(const int index,BVJournalRow &row)
     { if(index<0 || index>=ArraySize(m_rows)) return false; row=m_rows[index]; return true; }
   bool Put(const string kind,const string key,const string a="",const string b="",const string c="")
     {
      if(m_handle==INVALID_HANDLE || kind=="" || key=="") return false;
      string fields=kind+key+a+b+c;
      if(StringFind(fields,"\t")>=0 || StringFind(fields,"\r")>=0 || StringFind(fields,"\n")>=0) return false;
      BVJournalRow r; r.kind=kind; r.key=key; r.a=a; r.b=b; r.c=c; r.time=TimeCurrent();
      string line=kind+"\t"+IntegerToString((long)r.time)+"\t"+key+"\t"+a+"\t"+b+"\t"+c+"\r\n";
      if(FileWriteString(m_handle,line)==0) return false;
      FileFlush(m_handle);
      AddRow(r);
      return true;
     }
   void Close(void) { if(m_handle!=INVALID_HANDLE) FileClose(m_handle); m_handle=INVALID_HANDLE; }
  };
// Uniform escaping: an event ID is included in every CSV for independent audit.
string BVCSVCell(string value)
  { StringReplace(value,"\r"," "); StringReplace(value,"\n"," "); StringReplace(value,"\t"," "); StringReplace(value,"\"","\"\""); return "\""+value+"\""; }
void BVCSVAdd(string &line,const string value)
  { if(line!="") line+=","; line+=BVCSVCell(value); }
string BVNum(const double value) { return DoubleToString(value,10); }
int BVOpenCSV(const string path,const string header)
  {
   int h=FileOpen(path,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   if(h==INVALID_HANDLE) return h;
   if(FileSize(h)==0) { FileWriteString(h,header+"\r\n"); FileFlush(h); }
   FileSeek(h,0,SEEK_END); return h;
  }
// Parse the writer's single-line RFC4180 subset; reject torn/corrupted rows.
bool BVParseCSVRow(const string line,const int expected,string &id)
  {
   id=""; int i=0,count=0,length=StringLen(line);
   while(i<length)
     {
      if(StringGetCharacter(line,i)!=34) return false;
      i++; string value=""; bool closed=false;
      while(i<length)
        {
         ushort c=StringGetCharacter(line,i++);
         if(c==34)
           {
            if(i<length && StringGetCharacter(line,i)==34) { value+="\""; i++; }
            else { closed=true; break; }
           }
         else value+=ShortToString(c);
        }
      if(!closed) return false;
      if(count==0) id=value;
      count++;
      if(i==length) break;
      if(StringGetCharacter(line,i++)!=44 || i==length) return false;
     }
   return count==expected && id!="";
  }
#endif
