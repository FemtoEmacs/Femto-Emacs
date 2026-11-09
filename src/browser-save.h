/* Included by the native browser bridge. Browser requests never supply a
 * native pathname: only the original source buffer/file can be committed. */
static unsigned long long save_revision;
static void publish_snapshot(void);
#define BROWSER_FILE_LIMIT (16u*1024u*1024u)
static int same_text(const char *a,size_t an,const char *b,size_t bn)
{ return an==bn && (!an || (a&&b&&!memcmp(a,b,an))); }
static int read_disk(const char *path,char **text,size_t *len,int *exists)
{
 *text=NULL;*len=0;*exists=0;
 FILE *f=fopen(path,"rb");
 if(!f)return errno==ENOENT;
 struct stat st;int ok=!fstat(fileno(f),&st)&&S_ISREG(st.st_mode)&&st.st_size>=0&&st.st_size<=BROWSER_FILE_LIMIT;
 if(ok){*len=(size_t)st.st_size;*text=malloc(*len+1);ok=*text&&fread(*text,1,*len,f)==*len&&fgetc(f)==EOF;}
 if(fclose(f))ok=0;
 if(!ok){free(*text);*text=NULL;return 0;}
 (*text)[*len]=0;*exists=1;return 1;
}
static int resolve_target(const char *path,char resolved[4096])
{
 if(realpath(path,resolved))return 1;
 if(errno!=ENOENT)return 0;
 char parent[4096],base[4096];snprintf(parent,sizeof parent,"%s",path);
 char *slash=strrchr(parent,'/');if(!slash)return 0;
 snprintf(base,sizeof base,"%s",slash+1);if(!*base)return 0;
 if(slash==parent)slash[1]=0;else *slash=0;
 char actual[4096];if(!realpath(parent,actual))return 0;
 return snprintf(resolved,4096,"%s/%s",actual,base)<4096;
}
static void capture_save_target(void)
{
 *source_path=0;*save_path=0;disk_known=0;save_revision=0;
 if(!*source_name)return;
 if(source_name[0]=='/')snprintf(source_path,sizeof source_path,"%s",source_name);
 else {char cwd[4096];if(!getcwd(cwd,sizeof cwd))return;
  if(snprintf(source_path,sizeof source_path,"%s/%s",cwd,source_name)>=(int)sizeof source_path){*source_path=0;return;}}
 if(!resolve_target(source_path,save_path))return;
 disk_known=read_disk(save_path,&disk_baseline,&disk_len,&disk_exists);
}
static int live_source(void)
{
 for(buffer_t *b=bheadp;b;b=b->b_next)if(b==source&&b->b_id==source_id)return 1;
 return 0;
}
/* Why the browser's text may not go into the native buffer now, or NULL */
enum {SOURCE_OK,SOURCE_CLOSED,SOURCE_RENAMED,SOURCE_READONLY,SOURCE_EDITED};
static int source_problem(const char *text,size_t len)
{
 if(!live_source())return SOURCE_CLOSED;
 if(strcmp(source->b_fname,source_name))return SOURCE_RENAMED;
 if(source->b_flags&B_READONLY)return SOURCE_READONLY;
 size_t n;char *now=snapshot(source,&n);
 int ok=now&&(same_text(now,n,baseline,baseline_len)||same_text(now,n,text,len));free(now);
 return ok?SOURCE_OK:SOURCE_EDITED;
}
static int source_unchanged(const char *text,size_t len){return source_problem(text,len)==SOURCE_OK;}
/* What a refused browser save tells you, in both windows */
static void problem_message(int problem,char *message,size_t size)
{
 const char *keep="Your text is kept in both windows (here and in a *web-* buffer of the native window).";
 if(problem==SOURCE_READONLY)
  snprintf(message,size,"Not saved: the native buffer is read-only. %s C-x C-q in the native window makes it writable; then C-x C-s here saves.",keep);
 else if(problem==SOURCE_EDITED)
  snprintf(message,size,"Not saved: the native buffer was edited after C-c d. %s M-x native-window-update puts your text in the native buffer (its edits go to a *native-* buffer); then C-x C-s saves.",keep);
 else
  snprintf(message,size,"Not saved: the native buffer was %s. %s M-x native-window-update opens the file again in the native window with your text; then C-x C-s saves.",
	   problem==SOURCE_CLOSED?"closed":"saved under another name",keep);
}
static int replace_source(const char *text,size_t len)
{
 buffer_t *old=curbp;point_t point=source->b_point;int active=mark_active;
 curbp=source;
 size_t n;char *now=snapshot(source,&n);int same=now&&same_text(now,n,text,len);free(now);
 if(!same){
  fe_delete_region(0,document_size(source));fe_insert_bytes(0,(char*)text,(long)len);
  now=snapshot(source,&n);int ok=now&&same_text(now,n,text,len);free(now);
  if(!ok){curbp=old;return 0;}
  source->b_flags|=B_MODIFIED;
 }
 source->b_point=point<(point_t)len?point:(point_t)len;
 while(source->b_point>0&&source->b_point<(point_t)len&&((unsigned char)text[source->b_point]&0xc0)==0x80)source->b_point--;
 b2w_all_windows(source);curbp=old;
 mark_active=old==source?0:active;
 return 1;
}
static void remember_browser_text(const char *text,size_t len)
{
 char *p=malloc(len+1);if(!p)return;
 int changed=!same_text(baseline,baseline_len,text,len);
 memcpy(p,text,len);p[len]=0;free(baseline);baseline=p;baseline_len=len;
 if(changed)save_revision++;
 publish_snapshot();
}
/* Version and text live in the same atomic packet so a newly opened
 * browser cannot accidentally associate stale contents with a new version. */
static void publish_snapshot(void)
{
 char temp[8192],path[8192];snprintf(temp,sizeof temp,"%s/snapshot.new",session);snprintf(path,sizeof path,"%s/snapshot",session);
 FILE *f=fopen(temp,"wb");if(!f)return;
 int modified=!disk_known||!disk_exists||!same_text(baseline,baseline_len,disk_baseline,disk_len);
 int ok=fprintf(f,"%llu %d\n",save_revision,modified)>0&&fwrite(baseline,1,baseline_len,f)==baseline_len;
 if(fclose(f))ok=0;if(ok)rename(temp,path);else unlink(temp);
}
static int prepare_source_import(size_t len)
{
 buffer_t *old=curbp;curbp=source;
 unsigned long errors=runtime_failure_serial();
 int ok=growgap(source,(point_t)len+1)&&call_lisp_event("browser-save","")&&runtime_failure_serial()==errors;
 curbp=old;return ok;
}
static void mark_source_saved(void)
{
 source->b_flags&=~B_MODIFIED;record_change(source,'s',0,NULL,0);
}
static void keep_conflict(const char *text,size_t len,const char *why)
{
 static unsigned serial;static buffer_t *previous;static long previous_id,previous_source_id;
 for(buffer_t *b=bheadp;b;b=b->b_next)if(b==previous&&b->b_id==previous_id&&previous_source_id==source_id&&!b->b_fname[0]){
  size_t n;char *old=snapshot(b,&n);int same=old&&same_text(old,n,text,len);free(old);
  if(same){if(curwp->w_bufp!=b){disassociate_b(curwp);associate_b2w(b,curwp);}curbp=b;fe_message((char*)why);return;}
 }
 char name[NBUFN];
 do{snprintf(name,sizeof name,"*web-%u*",++serial);}while(find_buffer(name,FALSE));
 buffer_t *bp=find_buffer(name,TRUE);if(!bp)return;
 previous=bp;previous_id=bp->b_id;previous_source_id=source_id;
 disassociate_b(curwp);curbp=bp;associate_b2w(bp,curwp);
 fe_insert_bytes(0,(char*)text,(long)len);bp->b_flags|=B_MODIFIED;bp->b_point=0;
 fe_message((char*)why);
}
static int disk_matches(void)
{
 char *now;size_t len;int exists;
 if(!read_disk(save_path,&now,&len,&exists))return 0;
 int same=exists==disk_exists&&(!exists||same_text(now,len,disk_baseline,disk_len));free(now);return same;
}
/* Atomic replacement keeps the previous file intact on write/close failure.
 * Recheck the captured disk contents immediately before the final rename. */
static int commit_disk(const char *text,size_t len)
{
 struct stat st;mode_t mode;
 if(!stat(save_path,&st)){
  if(!S_ISREG(st.st_mode)||!(st.st_mode&0222)||access(save_path,W_OK))return 500;
  mode=st.st_mode&0777;
 }else if(errno==ENOENT){mode_t mask=umask(0);umask(mask);mode=0666&~mask;}
 else return 500;
 char temp[4096];const char *last=strrchr(save_path,'/');if(!last)return 500;
 if(snprintf(temp,sizeof temp,"%.*s/.chezweb-save-XXXXXX",(int)(last-save_path),save_path)>=(int)sizeof temp)return 500;
 int fd=mkstemp(temp);if(fd<0)return 500;
 int ok=!fchmod(fd,mode);FILE *f=fdopen(fd,"wb");
 if(!f){close(fd);unlink(temp);return 500;}
 if(ok)ok=fwrite(text,1,len,f)==len&&!fflush(f)&&!fsync(fileno(f));
 if(fclose(f))ok=0;
 int result=500;
 if(ok){if(!disk_matches())result=409;else if(!rename(temp,save_path))result=200;}
 unlink(temp);return result;
}
static void remember_disk(const char *text,size_t len)
{
 char *p=malloc(len+1);if(!p){disk_known=0;return;}
 memcpy(p,text,len);p[len]=0;free(disk_baseline);disk_baseline=p;disk_len=len;disk_exists=1;disk_known=1;
}
static void save_reply(unsigned long long id,int code,const char *message)
{
 char temp[8192],path[8192];snprintf(temp,sizeof temp,"%s/save.result.new",session);snprintf(path,sizeof path,"%s/save.result",session);
 FILE *f=fopen(temp,"wb");if(!f)return;
 int ok=fprintf(f,"%llu\n%d\n%llu\n%s",id,code,save_revision,message)>0;if(fclose(f))ok=0;
 if(ok)rename(temp,path);else unlink(temp);
}
/* TEXT in a new buffer *native-N*, kept out of the way: no window shows it */
static void keep_native_copy(const char *text,size_t len,char *name,size_t size)
{
 static unsigned serial;
 char bname[NBUFN];
 do{snprintf(bname,sizeof bname,"*native-%u*",++serial);}while(find_buffer(bname,FALSE));
 buffer_t *bp=find_buffer(bname,TRUE),*old=curbp;
 snprintf(name,size,"%s",bp?bname:"");
 if(!bp)return;
 curbp=bp;fe_insert_bytes(0,(char*)text,(long)len);bp->b_flags|=B_MODIFIED;bp->b_point=0;curbp=old;
}
/* M-x native-window-update in the browser: its text replaces the native
 * buffer's, which needs no save to be safe -- nothing is written to disk.
 * A closed (or renamed) source is opened again from its file; native text
 * that is neither the browser's nor on disk goes to *native-N* first.  A
 * read-only buffer stays as it is: that was the user's choice. */
static int update_native(const char *text,size_t len,char *message,size_t size)
{
 if(!*source_path){snprintf(message,size,"Not updated: the native buffer has no file. Save it there first (C-x C-s), then C-c d.");return 422;}
 int problem=source_problem(text,len);
 if(problem==SOURCE_CLOSED||problem==SOURCE_RENAMED){
  /* the file opened again (or the buffer that visits it now), as C-x C-f does */
  buffer_t *bp=find_buffer_by_fname(source_name);
  if(!bp){snprintf(message,size,"Not updated: the native window cannot open %s again.",source_path);return 500;}
  disassociate_b(curwp);curbp=bp;associate_b2w(bp,curwp);
  if(!bp->b_fname[0]){(void)load_file(source_name);safe_strncpy(bp->b_fname,source_name,NAME_MAX);}
  source=bp;source_id=bp->b_id;
 }
 if(source->b_flags&B_READONLY){snprintf(message,size,"Not updated: the native buffer is read-only. C-x C-q in the native window makes it writable; then M-x native-window-update again.");return 409;}
 char kept[NBUFN]="";size_t n;char *now=snapshot(source,&n);
 if(!now){snprintf(message,size,"Not updated: cannot read the native buffer.");return 500;}
 if(!same_text(now,n,text,len)){
  char *disk;size_t dlen;int exists,on_disk=read_disk(save_path,&disk,&dlen,&exists)&&exists&&same_text(now,n,disk,dlen);
  free(disk);if(!on_disk)keep_native_copy(now,n,kept,sizeof kept);
 }
 free(now);
 if(!prepare_source_import(len)||!replace_source(text,len)){snprintf(message,size,"Not updated: the native buffer could not take the browser text.");return 500;}
 remember_browser_text(text,len);
 int disk_changed=disk_known&&!disk_matches();
 snprintf(message,size,"Native buffer updated from the browser%s%s. %s",
	  *kept?"; its own text is in ":"",kept,
	  disk_changed?"The file changed on disk since C-c d: C-x C-s in the native window decides which version it keeps.":"C-x C-s in either window saves the file.");
 return 200;
}
static int process_save_request(void)
{
 char path[8192],incoming[8192];snprintf(path,sizeof path,"%s/save.pending",session);snprintf(incoming,sizeof incoming,"%s/save.incoming",session);
 if(rename(path,incoming))return 0;
 FILE *f=fopen(incoming,"rb");if(!f){unlink(incoming);return 0;}
 char line[64];unsigned long long id,revision=0;char tail;
 if(!fgets(line,sizeof line,f)||sscanf(line,"%llu %c",&id,&tail)!=1||
    !fgets(line,sizeof line,f)||(sscanf(line,"%llu %c",&revision,&tail)!=1&&strcmp(line,"update\n"))){fclose(f);unlink(incoming);return 0;}
 int update=!strcmp(line,"update\n");
 long offset=ftell(f);fseek(f,0,SEEK_END);long length=ftell(f)-offset;
 if(length<0||length>BROWSER_FILE_LIMIT){fclose(f);unlink(incoming);save_reply(id,413,"File exceeds the browser save limit.");return 1;}
 fseek(f,offset,SEEK_SET);char *text=malloc((size_t)length+1);
 int ok=text&&fread(text,1,(size_t)length,f)==(size_t)length;if(fclose(f))ok=0;
 unlink(incoming);if(!ok){free(text);save_reply(id,500,"Cannot read the browser save request.");return 1;}
 text[length]=0;int code=500;char message[4608],resolved[4096];
 if(update){code=update_native(text,(size_t)length,message,sizeof message);fe_message(message);}
 else if(!*source_path){code=422;snprintf(message,sizeof message,"Choose a filename with Save As in a granted browser folder, or save the native buffer first.");}
 else if(!source_unchanged(text,(size_t)length)){
  code=409;problem_message(source_problem(text,(size_t)length),message,sizeof message);
  keep_conflict(text,(size_t)length,message);
 }else if(revision!=save_revision && !(same_text(text,(size_t)length,baseline,baseline_len)&&disk_known&&disk_matches())){
  code=409;snprintf(message,sizeof message,"Not saved: a newer document version exists. Your browser text is preserved; reopen the file before merging.");
  keep_conflict(text,(size_t)length,message);
 }else if(!disk_known||!resolve_target(source_path,resolved)||strcmp(resolved,save_path)||!disk_matches()){
  code=409;snprintf(message,sizeof message,"Not saved: the original file changed on disk. Both versions are preserved; resolve the conflict before saving.");
  keep_conflict(text,(size_t)length,message);
 }else if(!prepare_source_import((size_t)length)||!source_unchanged(text,(size_t)length)){
  snprintf(message,sizeof message,"Cannot prepare the native buffer. Browser changes remain unsaved.");
 }else{
  code=commit_disk(text,(size_t)length);
  if(code==200){
   int imported=replace_source(text,(size_t)length);
   remember_disk(text,(size_t)length);
   if(imported){remember_browser_text(text,(size_t)length);mark_source_saved();snprintf(message,sizeof message,"Saved %s",source_path);}
   else snprintf(message,sizeof message,"Saved %s; reopen the native file to refresh its buffer.",source_path);
  }else if(code==409)snprintf(message,sizeof message,"Not saved: the file changed during saving. Browser changes remain unsaved.");
  else snprintf(message,sizeof message,"Save failed for %s. Browser changes remain unsaved; check write permissions and retry.",source_path);
  fe_message(message);
 }
 save_reply(id,code,message);free(text);return 1;
}
/* An explicit browser-local save may refer to this same physical document.
 * Reread only the fixed native source file; the browser supplies no pathname.
 * Preserve native edits if it has diverged from the last shared snapshot. */
static int refresh_native_file(void)
{
 char path[8192];snprintf(path,sizeof path,"%s/refresh",session);if(unlink(path))return 0;
 if(!live_source()||!*save_path||strcmp(source->b_fname,source_name))return 0;
 char *text;size_t len;int exists;if(!read_disk(save_path,&text,&len,&exists)||!exists)return 0;
 if(disk_known&&same_text(text,len,disk_baseline,disk_len)){free(text);return 0;}
 if(source_unchanged(text,len)&&prepare_source_import(len)&&replace_source(text,len)){
  remember_disk(text,len);remember_browser_text(text,len);mark_source_saved();fe_message("Browser-saved file reloaded; the native buffer is up to date.");
 }else keep_conflict(text,len,"File changed on disk; native edits were preserved. Review the browser conflict buffer.");
 free(text);return 1;
}
