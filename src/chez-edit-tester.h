/* Included only by the native tester: real key paths, no simulated edits. */
extern void fe_forward_char(int);
static int edit_probe(const char *action)
{
 unsigned long before=edit_stats_serial;
 call_lisp_event("tester-history",(char*)action);
 return edit_stats_serial!=before;
}
static int edit_eval(const char *code)
{
 return edit_probe(strstr(code,"begin") ? "begin" : "end");
}
static int edit_metrics(long values[8])
{
 if(!edit_probe("stats"))return 0;
 memcpy(values,edit_values,sizeof edit_values);
 return 1;
}
static int edit_key(struct run *r, buffer_t *bp, const char *bytes, int count)
{
 if (screen_test_cancelled()) { r->cancelled=1; return 0; }
 if (!tester_inject_key_bytes(bytes, count)) return 0;
 input = get_key(key_map, &key_return);
 editor_dispatch_key();
 return curbp == bp && bp->b_point >= 0 && bp->b_point <= document_size(bp);
}
static int edit_show(struct run *r, buffer_t *bp)
{
 if (curbp != bp || bp->b_point < 0 || bp->b_point > document_size(bp)) return 0;
 update_display(); screen_refresh(); screen_pause((int)r->delay);
 return 1;
}
static unsigned edit_chars(const char *text, unsigned from, unsigned to)
{
 unsigned n = 0;
 for (unsigned i = from; i < to; i++) if (((unsigned char)text[i] & 0xc0) != 0x80) n++;
 return n;
}
static int edit_move(struct run *r, buffer_t *bp, unsigned target)
{
 if (target > r->bytes || (target < r->bytes && ((unsigned char)r->expected[target] & 0xc0) == 0x80)) return 0;
 unsigned line = 1, start = 0;
 for (unsigned i = 0; i < target; i++) if (r->expected[i] == '\n') { line++; start = i+1; }
 unsigned column = edit_chars(r->expected, start, target);
 /* M-g is the counted equivalent of moving down to the selected logical
  * line; unlike visual down it is independent of the viewport's wrapping. */
 char macro[16]; int n = snprintf(macro, sizeof macro, "\033g%u\r", line);
 if (n < 0 || n >= (int)sizeof macro || !edit_key(r,bp, macro, n) || !edit_key(r,bp, "\001", 1)) return 0;
 for (unsigned i = 0; i < column; i++) if (!edit_key(r,bp, "\006", 1)) return 0;
 return bp->b_point == target && fe_line_number((long)target) == (int)line && edit_show(r, bp);
}
static int edit_paste_matches(struct run *r, buffer_t *bp, unsigned from, unsigned to, unsigned destination)
{
 unsigned added = to - from;
 if (document_size(bp) != (point_t)r->bytes + added) return 0;
 for (unsigned i = 0; i < r->bytes + added; i++) {
  unsigned index = i < destination ? i : i < destination + added ? from + i - destination : i - added;
  if (*ptr(bp, i) != (unsigned char)r->expected[index]) return 0;
 }
 return 1;
}
static int edit_number_line(const char *line, const char *name, unsigned *v, unsigned n)
{
 size_t len = strlen(name);
 if (strncmp(line, name, len) || line[len] != ' ') return 0;
 const char *p = line + len + 1;
 for (unsigned i = 0; i < n; i++) {
  if (*p < '0' || *p > '9') return 0;
  errno = 0; char *end; unsigned long x = strtoul(p,&end,10);
  if (errno || x > 67108864) return 0;
  v[i] = (unsigned)x;
  if (i+1 == n) return *end == 0;
  if (*end != ' ') return 0;
  p = end+1;
 }
 return 0;
}
static int run_edit_test(struct run *r, const char *origin_name)
{
 buffer_t *bp = NULL;
 char name[NBUFN] = "", line[128], expected[64], path[128];
 long metrics[8], base = 0;
 unsigned char *saved_scrap = scrap;
 int saved_nscrap = nscrap;
 int isolated = 0, ok = 0, clipboard_restored = 0;
 unsigned long errors = runtime_failure_serial();
 scrap = NULL; nscrap = 0;
 editing_active = 1;
 isolated = 1;
 if (!edit_eval("(tester-history-begin)")) goto finish;
 snprintf(r->header, sizeof r->header, "H 3 %u %u %u\n", r->file_count, r->edit_cycles, r->seed);
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
  snprintf(line,sizeof line,"BASE %ld\n",base);
  if (!send_line(r,line)) goto finish;
  for (unsigned cycle=0; cycle<r->edit_cycles; cycle++) {
   unsigned v[4];
   if (!read_reply(r,line,sizeof line) || !edit_number_line(line,"E",v,4) || v[0]!=cycle || v[1]>v[2] || v[2]>r->bytes || v[3]>r->bytes || edit_chars(r->expected,v[1],v[2])>200) goto finish;
   char command[128];
   int command_len=snprintf(command,sizeof command,"%s\n",line);
   if(command_len<0||command_len>=(int)sizeof command||!append_trace(r,command))goto finish;
   if (!edit_move(r,bp,v[1]) || !edit_key(r,bp,"\000",1)) goto finish;
   unsigned chars=edit_chars(r->expected,v[1],v[2]);
   fe_forward_char((int)chars);
   if(bp->b_point!=v[2] || !edit_show(r,bp) || !edit_key(r,bp,"\033w",2)) goto finish;
   int copied = nscrap==(int)(v[2]-v[1]) && (!nscrap || (scrap && !memcmp(scrap,r->expected+v[1],nscrap))) && fixture_intact(bp,r) && edit_probe("copy");
   /* Empty documents exercise an empty paste without importing user clipboard. */
   if (!chars && !scrap) { scrap=calloc(1,1);nscrap=0; }
   if (!edit_move(r,bp,v[3]) || !edit_key(r,bp,"\031",1) || !edit_show(r,bp)) goto finish;
   int pasted = edit_paste_matches(r,bp,v[1],v[2],v[3]);
   if (!edit_key(r,bp,"\037",1) || !edit_show(r,bp)) goto finish;
   int restored = fixture_intact(bp,r) && !(bp->b_flags & B_MODIFIED);
   if (!edit_key(r,bp,"\033<",2) || !edit_show(r,bp) || !edit_metrics(metrics)) goto finish;
   snprintf(line,sizeof line,"R %u %u %u %u %d %d %d %ld %ld %ld %ld %ld %ld %ld %ld %ld %u\n",
     cycle,v[1],v[2],v[3],copied,pasted,restored,(long)bp->b_point,
     metrics[0],metrics[1],metrics[2],metrics[3],metrics[4],metrics[5],metrics[6],metrics[7],runtime_failure_serial()!=errors);
   if (!append_trace(r,line) || !send_line(r,line)) goto finish;
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
   msg("chez-tester edit: file %u/%u cycle %u/%u; ring %ld, undo %ld/%ld (%ld bytes)",f+1,r->file_count,cycle+1,r->edit_cycles,metrics[0],metrics[2],metrics[3],metrics[4]);
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
  if(!edit_metrics(metrics)||metrics[7]!=base)goto finish;
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
 editing_active=0;
 return ok;
}
