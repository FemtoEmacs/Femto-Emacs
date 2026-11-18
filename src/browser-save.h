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
/* One rule (15 November 2026): C-x C-s in either window saves the file and
 * puts its text in the other window.  The native side of that is the buffer
 * that visits the file now: the one C-c d opened, or, after C-x k and C-x
 * C-f, or a Save As elsewhere, another buffer that visits the same file.
 * Returns 1 and makes it the source, or 0 when no buffer visits the file. */
static int attach_source(void)
{
 if(live_source()&&!strcmp(source->b_fname,source_name))return 1;
 if(!*save_path)return 0;
 for(buffer_t *b=bheadp;b;b=b->b_next){
  char resolved[4096];
  if(!b->b_fname[0]||!resolve_target(b->b_fname,resolved)||strcmp(resolved,save_path))continue;
  source=b;source_id=b->b_id;safe_strncpy(source_name,b->b_fname,sizeof source_name);
  return 1;
 }
 return 0;
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
static int disk_matches(void)
{
 char *now;size_t len;int exists;
 if(!read_disk(save_path,&now,&len,&exists))return 0;
 int same=exists==disk_exists&&(!exists||same_text(now,len,disk_baseline,disk_len));free(now);return same;
}
/* "#name#", the recovery file's name, for messages */
static const char *recovery_name(void)
{
 static char name[sizeof source_path+2];
 const char *base=strrchr(source_path,'/');
 snprintf(name,sizeof name,"#%s#",base?base+1:source_path);
 return name;
}
/* Replace the recovery file atomically, including when it already exists. */
static int save_recovery(const char *text,size_t len)
{
 char path[4096],temp[4096];
 const char *name=strrchr(source_path,'/');
 if(!name)return 0;
 int parent=(int)(name-source_path);
 if(snprintf(path,sizeof path,"%.*s/#%s#",parent,source_path,name+1)>=(int)sizeof path ||
    snprintf(temp,sizeof temp,"%.*s/.chezweb-recovery-XXXXXX",parent,source_path)>=(int)sizeof temp)return 0;
 int fd=mkstemp(temp);
 if(fd<0)return 0;
 FILE *f=fdopen(fd,"wb");
 if(!f){close(fd);unlink(temp);return 0;}
 int ok=fwrite(text,1,len,f)==len;
 if(fclose(f))ok=0;
 if(ok)ok=rename(temp,path)==0;
 if(!ok)unlink(temp);
 return ok;
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
static int process_save_request(void)
{
 char path[8192],incoming[8192];snprintf(path,sizeof path,"%s/save.pending",session);snprintf(incoming,sizeof incoming,"%s/save.incoming",session);
 if(rename(path,incoming))return 0;
 FILE *f=fopen(incoming,"rb");if(!f){unlink(incoming);return 0;}
 char line[64];unsigned long long id,revision=0;char tail;
 if(!fgets(line,sizeof line,f)||sscanf(line,"%llu %c",&id,&tail)!=1||
    !fgets(line,sizeof line,f)||(sscanf(line,"%llu %c",&revision,&tail)!=1&&strcmp(line,"backup\n"))){fclose(f);unlink(incoming);return 0;}
 int backup=!strcmp(line,"backup\n");
 long offset=ftell(f);fseek(f,0,SEEK_END);long length=ftell(f)-offset;
 if(length<0||length>BROWSER_FILE_LIMIT){fclose(f);unlink(incoming);save_reply(id,413,"File exceeds the browser save limit.");return 1;}
 fseek(f,offset,SEEK_SET);char *text=malloc((size_t)length+1);
 int ok=text&&fread(text,1,(size_t)length,f)==(size_t)length;if(fclose(f))ok=0;
 unlink(incoming);if(!ok){free(text);save_reply(id,500,"Cannot read the browser save request.");return 1;}
 text[length]=0;int code=500;char message[4608],resolved[4096];
 if(backup){
  code=save_recovery(text,(size_t)length)?200:500;
  snprintf(message,sizeof message,"%s",code==200?"Previous browser edits saved in the recovery file.":"Could not write the recovery file.");
 }else if(!*source_path){code=422;snprintf(message,sizeof message,"Save As to give this document a filename first.");}
 else {
  char *disk=NULL,*draft=NULL;
  size_t disk_size=0,draft_size=0;
  int exists=0;
  int attached=attach_source();
  if(attached)draft=snapshot(source,&draft_size);
  int recover=attached&&(source->b_flags&B_MODIFIED)&&
   !same_text(draft,draft_size,text,(size_t)length);
  if(attached&&(source->b_flags&B_READONLY)){
   /* the user's choice, as in the native window: the file is not written */
   code=409;
   snprintf(message,sizeof message,"Not saved: the native buffer of %s is read-only (C-x C-q there makes it writable). Browser changes remain unsaved.",source_path);
  }else if(!resolve_target(source_path,resolved)||strcmp(resolved,save_path)||
     !read_disk(save_path,&disk,&disk_size,&exists)||(attached&&!draft)){
   snprintf(message,sizeof message,"Cannot read the document. Browser changes remain unsaved.");
  }else if(recover&&!save_recovery(draft,draft_size)){
   snprintf(message,sizeof message,"Cannot write the native recovery file. Both drafts remain open.");
  }else if(attached&&!prepare_source_import((size_t)length)){
   snprintf(message,sizeof message,"Cannot prepare the native buffer. Browser changes remain unsaved.");
  }else{
   free(disk_baseline);disk_baseline=disk;disk=NULL;
   disk_len=disk_size;disk_exists=exists;disk_known=1;
   code=commit_disk(text,(size_t)length);
   if(code==200){
    remember_disk(text,(size_t)length);
    /* the native buffer has the file as written: its next C-x C-s must
       not take this save for another program's change (gap.c) */
    if(attached&&replace_source(text,(size_t)length)){mark_source_saved();buffer_remember_disk(source,source->b_fname);}
    remember_browser_text(text,(size_t)length);
    snprintf(message,sizeof message,"Saved %s%s%s%s",source_path,recover?"; previous native edits saved in ":"",recover?recovery_name():"",recover?".":"");
   }else snprintf(message,sizeof message,"Save failed for %s. Browser changes remain unsaved.",source_path);
  }
  free(disk);free(draft);
  fe_message(message);
 }
 if(backdoor_on)backdoor_note("  chezweb: browser %s, %ld bytes: %d %s",backup?"recovery request":"C-x C-s",length,code,message);
 save_reply(id,code,message);free(text);return 1;
}
/* A browser save into a granted folder (C-x C-f, TAB) may write this same
 * file itself; the page then asks for this refresh.  As with any C-x C-s:
 * the native buffer that visits the file takes the saved text, and its own
 * unsaved edits go to the recovery file.  A read-only buffer keeps its text. */
static int refresh_native_file(void)
{
 char path[8192];snprintf(path,sizeof path,"%s/refresh",session);if(unlink(path))return 0;
 if(!attach_source())return 0;
 char *text;size_t len;int exists;if(!read_disk(save_path,&text,&len,&exists)||!exists)return 0;
 if(disk_known&&same_text(text,len,disk_baseline,disk_len)){free(text);return 0;}
 size_t n;char *draft=snapshot(source,&n);
 int recover=draft&&(source->b_flags&B_MODIFIED)&&!same_text(draft,n,text,len);
 char message[4608];
 if(source->b_flags&B_READONLY)
  snprintf(message,sizeof message,"%s changed on disk (saved from the browser); this buffer is read-only and keeps its text.",source_path);
 else if(!draft||(recover&&!save_recovery(draft,n)))
  snprintf(message,sizeof message,"%s changed on disk, but the native edits could not be kept in %s: this buffer keeps them.",source_path,recovery_name());
 else if(prepare_source_import(len)&&replace_source(text,len)){
  remember_disk(text,len);remember_browser_text(text,len);mark_source_saved();buffer_remember_disk(source,source->b_fname);
  snprintf(message,sizeof message,"Saved from the browser; this buffer has the text%s%s%s",recover?", and the native edits are in ":"",recover?recovery_name():"",".");
 }else snprintf(message,sizeof message,"%s changed on disk, but this buffer could not take the text.",source_path);
 fe_message(message);
 if(backdoor_on)backdoor_note("  chezweb: browser save into a granted folder, %ld bytes: %s",(long)len,message);
 free(draft);free(text);return 1;
}
