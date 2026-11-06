/* Native adapter for the Lean search-return protocol (included after edit helpers). */
extern void fe_set_scrap(char *);
_Static_assert(STRBUF_M > 32, "search tester requires room for a 32-byte query");
static int run_search_test(struct run *r, const char *origin_name)
{
 buffer_t *bp = NULL;
 char name[NBUFN] = "", line[128], expected[64], path[128];
 long metrics[8], baseline[8], saved_metrics[8], base = 0;
 char saved_search[STRBUF_M];
 memcpy(saved_search,searchtext,STRBUF_M);
 if(!edit_metrics(saved_metrics))return 0;
 unsigned char *saved_scrap = scrap;
 int saved_nscrap = nscrap;
 int isolated = 0, ok = 0, clipboard_restored = 0;
 unsigned long errors = runtime_failure_serial();
 scrap = NULL; nscrap = 0;
 editing_active = 1;
 isolated = 1;
 if (!edit_eval("(tester-history-begin)")) goto finish;
 fe_set_scrap("chez-tester search baseline");
 nscrap=(int)strlen("chez-tester search baseline");
 if(!edit_probe("search-seed"))goto finish;
 snprintf(r->header, sizeof r->header, "H 4 %u %u %u\n", r->file_count, r->edit_cycles, r->seed);
 if (!new_batch(r) || !send_line(r,"READY\n")) goto finish;
 for (unsigned f = 0; f < r->file_count; f++) {
  unsigned header[2];
  if (!read_reply(r,line,sizeof line) || !edit_number_line(line,"FILE",header,2) || header[0] != f || header[1] > 67108864) goto finish;
  r->bytes = header[1];
  snprintf(path,sizeof path,"%s/input-%u.md",r->snapshot_dir,f);
  FILE *file = fopen(path,"rb");
  r->expected = malloc(r->bytes ? r->bytes : 1);
  if (!file || !r->expected) { if(file) fclose(file); goto finish; }
  int loaded = fread(r->expected,1,r->bytes,file) == r->bytes && fgetc(file) == EOF;
  if (fclose(file)) loaded = 0;
  if (!loaded) goto finish;
  for (unsigned i = 0; i < 10000; i++) { snprintf(name,sizeof name,"*et%04u*",i); if (!find_buffer(name,FALSE)) break; name[0]=0; }
  if (!name[0] || !(bp=find_buffer(name,TRUE)) || !growgap(bp,r->bytes)) goto finish;
  memcpy(bp->b_gap,r->expected,r->bytes);bp->b_gap+=r->bytes;
  safe_strncpy(bp->b_fname,path,NAME_MAX);
  select_buffer(name);fe_read_mode(0);mark_active=0;bp->b_point=0;bp->b_col=0;
  if (!edit_metrics(metrics)) goto finish;
  base=metrics[7];
  /* Give search real nonempty done/redo stacks to preserve, without
   * changing the fixture text: insert/delete, then insert/undo. */
  if(!edit_key(r,bp,"Z",1)||!edit_key(r,bp,"\177",1)||
     !edit_key(r,bp,"Y",1)||!edit_key(r,bp,"\037",1)||!fixture_intact(bp,r)||
     !edit_metrics(metrics)||metrics[2]<1||metrics[3]<1)goto finish;
  memcpy(baseline,metrics,sizeof baseline);
  if(!edit_probe("search-baseline"))goto finish;
  snprintf(line,sizeof line,"BASE %ld\n",base);
  if (!send_line(r,line)) goto finish;
  for (unsigned cycle=0; cycle<r->edit_cycles; cycle++) {
   unsigned v[6];
   if (!read_reply(r,line,sizeof line) || !edit_number_line(line,"S",v,6) ||
       v[0]!=cycle || v[1]>r->bytes || v[2]>r->bytes || v[3]>1 || v[4]>v[5] || v[5]>r->bytes || v[5]-v[4]>32) goto finish;
   char command[64], query[33];
   int command_len=snprintf(command,sizeof command,"%s\n",line);
   if(command_len<0||command_len>=(int)sizeof command||!append_trace(r,command))goto finish;
   unsigned length=v[5]-v[4];
   if(length)memcpy(query,r->expected+v[4],length);
   else {strcpy(query,"chez-tester");length=(unsigned)strlen(query);}
   query[length]=0;
   for(unsigned i=0;i<length;i++)if((unsigned char)query[i]<32||query[i]==127)goto finish;
   int dirty=bp->b_flags & B_MODIFIED;
   if(!edit_move(r,bp,v[1])||!edit_move(r,bp,v[2]))goto finish;
   char keys[36];keys[0]=v[3] ? '\022' : '\023';memcpy(keys+1,query,length);keys[length+1]='\r';
   if(!edit_key(r,bp,keys,(int)length+2)||!edit_show(r,bp))goto finish;
   unsigned point=(unsigned)bp->b_point;
   int matched=0;
   if(v[3])matched=point<v[2] && point+length<=r->bytes && !memcmp(r->expected+point,query,length);
   else matched=point>=length && point-length>=v[2] && !memcmp(r->expected+point-length,query,length);
   int query_same=strlen(searchtext)==length && !memcmp(searchtext,query,length);
   int intact=fixture_intact(bp,r), dirty_same=(bp->b_flags & B_MODIFIED)==dirty;
   if(!edit_move(r,bp,v[1])||!edit_probe("search-check"))goto finish;
   memcpy(metrics,edit_values,sizeof edit_values);
   intact=intact && fixture_intact(bp,r);
   dirty_same=dirty_same && ((bp->b_flags & B_MODIFIED)==dirty);
   query_same=query_same && strlen(searchtext)==length && !memcmp(searchtext,query,length);
   int histories=!memcmp(metrics,baseline,sizeof baseline) && scrap &&
     nscrap==(int)strlen("chez-tester search baseline") &&
     !memcmp(scrap,"chez-tester search baseline",(size_t)nscrap);
   snprintf(line,sizeof line,"R %u %u %d %d %d %ld %d %d %u %u\n",
     cycle,point,matched,intact,dirty_same,(long)bp->b_point,histories,query_same,length,runtime_failure_serial()!=errors);
   if(!append_trace(r,line)||!send_line(r,line))goto finish;
   if(length>r->search_peak)r->search_peak=length;
   r->seq++;
   snprintf(expected,sizeof expected,"ACK %u",r->seq);
   if (!receive(r,expected)) goto finish;
   r->acked=r->seq;
   if(metrics[0]>r->ring_peak)r->ring_peak=metrics[0];
   if(metrics[1]>r->ring_bytes_peak)r->ring_bytes_peak=metrics[1];
   if(metrics[4]>r->undo_accounted_peak)r->undo_accounted_peak=metrics[4];
   if(metrics[5]>r->undo_bytes_peak)r->undo_bytes_peak=metrics[5];
   /* Each cycle is acknowledged independently before its diagnostic slot is reused. */
   if (!new_batch(r)) goto finish;
   msg("chez-tester search: file %u/%u cycle %u/%u; returned to %u, histories unchanged",f+1,r->file_count,cycle+1,r->edit_cycles,v[1]);
   dispmsg();screen_refresh();
  }
  unsigned closed[1];
  if(!read_reply(r,line,sizeof line)||!edit_number_line(line,"CLOSE",closed,1)||closed[0]!=f)goto finish;
  select_buffer((char*)origin_name);delete_buffer(bp);bp=NULL;free(r->expected);r->expected=NULL;
  if(!edit_metrics(metrics)||metrics[7]!=base)goto finish;
  snprintf(line,sizeof line,"CLEAN %u %ld\n",f,base);
  if(!send_line(r,line))goto finish;
 }
 {
  unsigned done[1];
  if(!read_reply(r,line,sizeof line)||!edit_number_line(line,"DONE",done,1)||done[0]!=r->file_count*r->edit_cycles)goto finish;
  if(!edit_eval("(tester-history-end)"))goto finish;
  isolated=0;
  free(scrap);scrap=saved_scrap;nscrap=saved_nscrap;clipboard_restored=1;
  memcpy(searchtext,saved_search,STRBUF_M);
  r->search_restored=!memcmp(searchtext,saved_search,STRBUF_M);
  if(!r->search_restored||!send_line(r,"SEARCH-RESTORED 1\n"))goto finish;
  if(!edit_metrics(metrics)||memcmp(metrics,saved_metrics,sizeof saved_metrics))goto finish;
  snprintf(line,sizeof line,"COMPLETE %ld %ld %ld %ld %ld %ld %ld %ld\n",metrics[0],metrics[1],metrics[2],metrics[3],metrics[4],metrics[5],metrics[6],metrics[7]);
  if(!send_line(r,line))goto finish;
  r->histories_restored=1;
  snprintf(expected,sizeof expected,"PASS %u",done[0]);
  if(!receive(r,expected))goto finish;
  ok=1;
 }
finish:
 if(bp){select_buffer((char*)origin_name);delete_buffer(bp);}
 if(isolated && !edit_eval("(tester-history-end)"))ok=0;
 if(!clipboard_restored){free(scrap);scrap=saved_scrap;nscrap=saved_nscrap;}
 memcpy(searchtext,saved_search,STRBUF_M);
 r->search_restored=!memcmp(searchtext,saved_search,STRBUF_M);
 editing_active=0;
 return ok;
}
