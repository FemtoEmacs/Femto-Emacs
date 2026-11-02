/* Native Wasmtime host: no JavaScript engine or Node process. */
#include "native-host.h"
#include <wasmtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <errno.h>
#ifdef _WIN32
#define strdup _strdup
#endif
#include <sys/stat.h>
typedef struct entry { wasmtime_val_t key,value; struct entry *next; } entry;
typedef struct table { wasmtime_val_t object; entry *items; struct table *next; } table;
struct sc_module {
 char *compiler_input;
 wasmtime_store_t *store; wasmtime_context_t *ctx; wasmtime_instance_t instance;
 wasmtime_module_t *module; wasmtime_val_t closure; int kept;
 char *out,*number; size_t len,cap,nlen; table *tables; entry *symbols;
 sc_editor_fn editor; void *user;
 wasmtime_memory_t memory; int has_memory; sc_ccall_fn ccall; void *ccall_user;
 wasmtime_func_t call3; int has_call3;
};
static wasm_engine_t *engine;
static void append(sc_module *m,const char *s,size_t n) {
 if(m->len+n+1>m->cap){m->cap=(m->len+n+1)*2;m->out=realloc(m->out,m->cap);if(!m->out)abort();}
 memcpy(m->out+m->len,s,n);m->len+=n;m->out[m->len]=0;
}
static void uchar(sc_module *m,unsigned c) {
 char b[4];int n;if(c<128){b[0]=c;n=1;}else if(c<2048){b[0]=192|(c>>6);b[1]=128|(c&63);n=2;}else if(c<65536){b[0]=224|(c>>12);b[1]=128|((c>>6)&63);b[2]=128|(c&63);n=3;}else{b[0]=240|(c>>18);b[1]=128|((c>>12)&63);b[2]=128|((c>>6)&63);b[3]=128|(c&63);n=4;}append(m,b,n);
}
static char *errtext(wasmtime_error_t *e,wasm_trap_t *t) {
 wasm_name_t name; if(e)wasmtime_error_message(e,&name);else wasm_trap_message(t,&name);
 char *s=malloc(name.size+1);memcpy(s,name.data,name.size);s[name.size]=0;wasm_name_delete(&name);
 if(e)wasmtime_error_delete(e);if(t)wasm_trap_delete(t);
 if(strstr(s,"cast failure")){free(s);s=strdup("a value of the wrong type (illegal cast)");}
 /* the other traps a Scheme program meets, said as briefly */
 else if(strstr(s,"out of bounds array access")){free(s);s=strdup("an index out of range");}
 else if(strstr(s,"null reference")||strstr(s,"null pointer")){free(s);s=strdup("a value of the wrong type (no value)");}
 else if(strstr(s,"call stack exhausted")){free(s);s=strdup("the stack is exhausted (a recursion without end?)");}
 else if(strstr(s,"integer divide by zero")){free(s);s=strdup("a division by zero");}
 return s;
}
static int call(sc_module *m,const char *name,const wasmtime_val_t *args,size_t n,wasmtime_val_t *r,size_t nr,char **error) {
 wasmtime_extern_t fn;if(!wasmtime_instance_export_get(m->ctx,&m->instance,name,strlen(name),&fn)){*error=strdup("Missing compiler host export");return 0;}
 wasm_trap_t *trap=NULL;wasmtime_error_t *e=wasmtime_func_call(m->ctx,&fn.of.func,args,n,r,nr,&trap);wasmtime_extern_delete(&fn);
 if(e||trap){*error=errtext(e,trap);return 0;}return 1;
}
static wasmtime_val_t i32(int x){wasmtime_val_t v={.kind=WASMTIME_I32};v.of.i32=x;return v;}
static wasmtime_val_t refint(sc_module *m,int x){wasmtime_val_t v={.kind=WASMTIME_ANYREF};wasmtime_anyref_from_i31(m->ctx,(unsigned)x,&v.of.anyref);return v;}
static char *tostr_size(sc_module *m,const wasmtime_val_t *s,size_t *size) {
 char *error=NULL;wasmtime_val_t n;if(!call(m,"string_length",s,1,&n,1,&error)){free(error);return NULL;}
 if(n.of.i32<0||n.of.i32>0x10000000)return NULL;
 sc_module b={0};for(int k=0;k<n.of.i32;k++){wasmtime_val_t a[2]={*s,i32(k)},r;if(!call(m,"string_ref",a,2,&r,1,&error)){free(error);free(b.out);return NULL;}uchar(&b,(unsigned)r.of.i32);}
 if(size)*size=b.len;
 return b.out?b.out:strdup("");
}
static char *tostr(sc_module *m,const wasmtime_val_t *s){return tostr_size(m,s,NULL);}
static int fromstr_size(sc_module *m,const char *s,size_t size,wasmtime_val_t *r) {
 int count=0;for(const unsigned char *p=(const unsigned char*)s;p<(const unsigned char*)s+size;p++)if((*p&192)!=128)count++;
 wasmtime_val_t n=i32(count);char *error=NULL;if(!call(m,"string_new",&n,1,r,1,&error)){free(error);return 0;}
 int k=0;const unsigned char *p=(const unsigned char*)s;while(p<(const unsigned char*)s+size){unsigned c=*p++;if(c>=192){int more=(c<224?1:c<240?2:3);c&=(1u<<(6-more))-1;while(more--&&p<(const unsigned char*)s+size)c=(c<<6)|(*p++&63);}wasmtime_val_t a[3]={*r,i32(k++),i32(c)};if(!call(m,"string_set",a,3,NULL,0,&error)){free(error);wasmtime_val_unroot(r);return 0;}}
 return 1;
}
static int fromstr(sc_module *m,const char *s,wasmtime_val_t *r){return fromstr_size(m,s,strlen(s),r);}
static int same(sc_module *m,const wasmtime_val_t *a,const wasmtime_val_t *b){wasmtime_val_t args[2]={*a,*b},r;char *error=NULL;if(!call(m,"native_ref_equal",args,2,&r,1,&error)){free(error);return 0;}return r.of.i32;}
static void clear_entries(entry **head){entry *e=*head;while(e){entry *n=e->next;wasmtime_val_unroot(&e->key);wasmtime_val_unroot(&e->value);free(e);e=n;}*head=NULL;}
/* Shortest round-trip decimal, with Scheme's .0 and JS host thresholds. */
static void flonum(double x,char *s,size_t n){
 if(isnan(x)){snprintf(s,n,"+nan.0");return;}
 if(isinf(x)){snprintf(s,n,x<0?"-inf.0":"+inf.0");return;}
 if(x==trunc(x)&&fabs(x)<1e21){snprintf(s,n,"%.0f.0",x);return;}
 int precision;char digits[128];
 for(precision=1;precision<17;precision++){snprintf(digits,sizeof digits,"%.*g",precision,x);if(strtod(digits,NULL)==x)break;}
 snprintf(digits,sizeof digits,"%.*g",precision,x);
 if(fabs(x)>=1e-6&&fabs(x)<1e21){
  int places=precision-1-(int)floor(log10(fabs(x)));if(places<0)places=0;
  snprintf(s,n,"%.*f",places,x);
 }else{
  char *exp=strchr(digits,'e');if(exp){int exponent=atoi(exp+1);*exp=0;snprintf(s,n,"%se%+d",digits,exponent);}else snprintf(s,n,"%s",digits);
 }
}
static double nowms(void){struct timespec ts;timespec_get(&ts,TIME_UTC);return ts.tv_sec*1000.0+ts.tv_nsec/1e6;}
static wasm_trap_t *trap_text(const char *s){return wasmtime_trap_new(s,strlen(s));}
typedef struct {sc_module *m;int op;} callback;
static wasm_trap_t *host(void *data,wasmtime_caller_t *caller,const wasmtime_val_t *a,size_t na,wasmtime_val_t *r,size_t nr){
 (void)caller;(void)na;(void)nr;callback *cb=data;sc_module *m=cb->m;char b[128],*s=NULL,*text=NULL;int op;
 switch(cb->op){
 case 0:uchar(m,a[0].of.i32);break;
 case 1:flonum(a[0].of.f64,b,sizeof b);append(m,b,strlen(b));break;
 case 2:return trap_text("Scheme program raised an error");
 case 3:r->kind=WASMTIME_F64;r->of.f64=nowms();break;
 case 4:{double x=a[1].of.f64,y;switch(a[0].of.i32){case 0:y=exp(x);break;case 1:y=log(x);break;case 2:y=sin(x);break;case 3:y=cos(x);break;case 4:y=tan(x);break;case 5:y=atan(x);break;case 6:y=asin(x);break;default:y=acos(x);}r->kind=WASMTIME_F64;r->of.f64=y;break;}
 case 5:r->kind=WASMTIME_F64;r->of.f64=a[0].of.i32==0?pow(a[1].of.f64,a[2].of.f64):atan2(a[1].of.f64,a[2].of.f64);break;
 case 6:flonum(a[0].of.f64,b,sizeof b);*r=i32(a[1].of.i32>=0&&(size_t)a[1].of.i32<strlen(b)?(unsigned char)b[a[1].of.i32]:-1);break;
 case 7:m->number=realloc(m->number,m->nlen+2);m->number[m->nlen++]=(char)a[0].of.i32;m->number[m->nlen]=0;break;
 case 8:r->kind=WASMTIME_F64;r->of.f64=strtod(m->number?m->number:"",NULL);m->nlen=0;if(m->number)m->number[0]=0;break;
 case 9:{op=a[0].of.i32;entry **items=&m->symbols;table *t=NULL;if(op<8){for(t=m->tables;t&&!same(m,&t->object,&a[1]);t=t->next) {} if(op==0&&!t){t=calloc(1,sizeof *t);wasmtime_val_clone(&a[1],&t->object);t->next=m->tables;m->tables=t;}if(!t)return trap_text("Unknown native hash table");items=&t->items;}
  if(op==0){wasmtime_val_clone(&a[1],r);break;}entry **slot=items;while(*slot&&!same(m,&(*slot)->key,&a[2]))slot=&(*slot)->next;
  if(op==1||op==8){wasmtime_val_clone(*slot?&(*slot)->value:&a[3],r);break;}
  if(op==2||op==9){if(!*slot){*slot=calloc(1,sizeof **slot);wasmtime_val_clone(&a[2],&(*slot)->key);}else wasmtime_val_unroot(&(*slot)->value);wasmtime_val_clone(&a[3],&(*slot)->value);wasmtime_val_clone(&a[3],r);break;}
  if(op==3){if(*slot){entry *e=*slot;*slot=e->next;e->next=NULL;clear_entries(&e);}wasmtime_val_clone(&a[3],r);break;}
  if(op==4){int n=0;for(entry *e=*items;e;e=e->next)n++;*r=refint(m,n);break;}
  if(op==5){clear_entries(items);wasmtime_val_clone(&a[3],r);break;}
  if(op==6){wasmtime_val_clone(&a[3],r);for(entry *e=*items;e;e=e->next){wasmtime_val_t args[2]={e->value,*r},v;char *error=NULL;if(!call(m,"cons",args,2,&v,1,&error)){free(error);wasmtime_val_unroot(r);return trap_text("Cannot collect native table values");}wasmtime_val_unroot(r);*r=v;}break;}
  return trap_text("Unknown table operation");}
 case 10:{op=a[0].of.i32;s=tostr(m,&a[1]);if(!s)return trap_text("Invalid file name");FILE *f=NULL;
  if(m->compiler_input){
   if(op!=0 || strcmp(s,":schemer-request")){free(s);return trap_text("Compiler file access is restricted to its request");}
   int ok=fromstr(m,m->compiler_input,r);free(s);if(!ok)return trap_text("Cannot construct compiler input");break;
  }
  if(op==0){f=fopen(s,"rb");if(!f){*r=refint(m,0);free(s);break;}sc_module content={0};size_t n;char chunk[4096];while((n=fread(chunk,1,sizeof chunk,f)))append(&content,chunk,n);int bad=ferror(f);fclose(f);if(bad){free(content.out);free(s);return trap_text("Cannot read Scheme file");}if(!fromstr_size(m,content.out?content.out:"",content.len,r)){free(content.out);free(s);return trap_text("Cannot construct Scheme string");}free(content.out);}
  else if(op==1){size_t len=0;text=tostr_size(m,&a[2],&len);if(!text){free(s);return trap_text("Invalid file contents");}f=fopen(s,"wb");if(!f){free(text);free(s);return trap_text("Cannot write Scheme file");}int bad=fwrite(text,1,len,f)!=len;if(fclose(f))bad=1;free(text);if(bad){free(s);return trap_text("Cannot write Scheme file");}*r=refint(m,0);}
  else if(op==2){struct stat st;*r=refint(m,stat(s,&st)==0?1:0);}
  else if(op==3){if(remove(s)&&errno!=ENOENT){free(s);return trap_text("Cannot remove Scheme file");}*r=refint(m,0);}
  else{free(s);return trap_text("Unknown file operation");}free(s);break;}
 case 11:break;
 case 12:{int32_t id;
  /* a number: the bridge to C, its arguments in the memory */
  if(a[0].kind==WASMTIME_ANYREF&&wasmtime_anyref_i31_get_s(m->ctx,&a[0].of.anyref,&id)){
   if(!m->ccall)return trap_text("No C bridge installed");
   *r=refint(m,m->ccall(m,id,m->ccall_user));break;}}
  s=tostr(m,&a[0]);if(!s)return trap_text("Invalid editor request");text=m->editor?m->editor(s,m->user):strdup("error No editor callback installed");free(s);if(!text)return trap_text("Editor callback failed");int ok=fromstr(m,text,r);free(text);if(!ok)return trap_text("Cannot construct editor response");break;
 }return NULL;
}
static void ensure_engine(void){
 if(!engine){wasm_config_t *cfg=wasm_config_new();wasmtime_config_wasm_gc_set(cfg,true);wasmtime_config_wasm_exceptions_set(cfg,true);wasmtime_config_wasm_tail_call_set(cfg,true);engine=wasm_engine_new_with_config(cfg);}
}

/* ------------------------------------------------------------------
 * Machine code kept in a file.  Wasmtime turns a module's WebAssembly
 * into machine code before running it: several milliseconds a KB.  `make`
 * does it once for the editor's program (chezemax.wasm), and saves it
 * in a file (chezemax.cwasm): the fingerprint of the WebAssembly, then
 * Wasmtime's machine code.  A file made from other WebAssembly, or that
 * this Wasmtime cannot use (another version, another processor), is not
 * used: the WebAssembly is translated as before.
 * ------------------------------------------------------------------ */
static unsigned long long fingerprint(const unsigned char *bytes,size_t size){
 unsigned long long h=1469598103934665603ULL;           /* FNV-1a, 64 bits */
 for(size_t i=0;i<size;i++){h^=bytes[i];h*=1099511628211ULL;}
 return h^(unsigned long long)size;
}
#define CODE_MAGIC "SCcode1\n"
static wasmtime_module_t *load_code(const unsigned char *bytes,size_t size,const char *path){
 FILE *f=fopen(path,"rb");unsigned char head[16];wasmtime_module_t *module=NULL;
 if(!f)return NULL;
 unsigned long long want=fingerprint(bytes,size),got=0;
 if(fread(head,1,16,f)==16&&!memcmp(head,CODE_MAGIC,8)){
  for(int k=0;k<8;k++)got|=(unsigned long long)head[8+k]<<(8*k);
  if(got==want){
   fseek(f,0,SEEK_END);long n=ftell(f)-16;
   if(n>0){unsigned char *code=malloc((size_t)n);
    fseek(f,16,SEEK_SET);
    if(code&&fread(code,1,(size_t)n,f)==(size_t)n){
     wasmtime_error_t *e=wasmtime_module_deserialize(engine,code,(size_t)n,&module);
     if(e){wasmtime_error_delete(e);module=NULL;}}
    free(code);}}}
 fclose(f);return module;
}
int sc_code_save(const unsigned char *bytes,size_t size,const char *path,char **error){
 wasmtime_module_t *module=NULL;wasm_byte_vec_t code;char temp[4200];
 ensure_engine();
 wasmtime_error_t *e=wasmtime_module_new(engine,bytes,size,&module);
 if(!e)e=wasmtime_module_serialize(module,&code);
 if(module)wasmtime_module_delete(module);
 if(e){*error=errtext(e,NULL);return 0;}
 /* written under another name first, then renamed: never half a file */
 snprintf(temp,sizeof temp,"%s.tmp",path);
 FILE *f=fopen(temp,"wb");int ok=f!=NULL;
 if(f){unsigned long long h=fingerprint(bytes,size);unsigned char head[16];memcpy(head,CODE_MAGIC,8);
  for(int k=0;k<8;k++)head[8+k]=(unsigned char)(h>>(8*k));
  ok=fwrite(head,1,16,f)==16&&fwrite(code.data,1,code.size,f)==code.size;
  if(fclose(f))ok=0;}
 wasm_byte_vec_delete(&code);
 if(!ok||rename(temp,path)){remove(temp);*error=strdup("Cannot write the machine code");return 0;}
 return 1;
}

sc_module *sc_module_open(const unsigned char *bytes,size_t size,sc_editor_fn editor,void *user,char **error){
 return sc_module_open_code(bytes,size,NULL,editor,user,error);
}
sc_module *sc_module_open_code(const unsigned char *bytes,size_t size,const char *code_path,sc_editor_fn editor,void *user,char **error){
 ensure_engine();
 sc_module *m=calloc(1,sizeof *m);m->store=wasmtime_store_new(engine,NULL,NULL);m->ctx=wasmtime_store_context(m->store);m->editor=editor;m->user=user;
 wasmtime_error_t *e=NULL;
 if(code_path)m->module=load_code(bytes,size,code_path);
 if(!m->module){e=wasmtime_module_new(engine,bytes,size,&m->module);if(e){*error=errtext(e,NULL);sc_module_close(m);return NULL;}}
 wasm_importtype_vec_t imports;wasmtime_module_imports(m->module,&imports);wasmtime_extern_t *ext=calloc(imports.size,sizeof *ext);
 const char *names[]={"write_char","write_flonum","abort","now","math","math2","flonum_char","number_char","number_end","table","file","poll","editor"};
 for(size_t i=0;i<imports.size;i++){const wasm_name_t *name=wasm_importtype_name(imports.data[i]),*module=wasm_importtype_module(imports.data[i]);int op=-1;for(int k=0;k<13;k++)if(strlen(names[k])==name->size&&!memcmp(names[k],name->data,name->size))op=k;
  if(module->size==4&&!memcmp(module->data,"host",4)&&name->size==6&&!memcmp(name->data,"memory",6)){
   /* the bridge's memory: 1 MiB to start with, grown on demand */
   wasm_memorytype_t *mt=NULL;
   e=wasmtime_memorytype_new(16,false,0,false,false,16,&mt);
   if(!e)
    e=wasmtime_memory_new(m->ctx,mt,&m->memory);
   if(mt)
    wasm_memorytype_delete(mt);
   if(e){*error=errtext(e,NULL);free(ext);wasm_importtype_vec_delete(&imports);sc_module_close(m);return NULL;}
   m->has_memory=1;ext[i].kind=WASMTIME_EXTERN_MEMORY;ext[i].of.memory=m->memory;continue;}
  if(op<0||module->size!=4||memcmp(module->data,"host",4)){*error=strdup("Unsupported compiler host import");free(ext);wasm_importtype_vec_delete(&imports);sc_module_close(m);return NULL;}
  callback *cb=malloc(sizeof *cb);cb->m=m;cb->op=op;ext[i].kind=WASMTIME_EXTERN_FUNC;wasmtime_func_new(m->ctx,wasm_externtype_as_functype_const(wasm_importtype_type(imports.data[i])),host,cb,free,&ext[i].of.func);
 }
 wasm_trap_t *trap=NULL;e=wasmtime_instance_new(m->ctx,m->module,ext,imports.size,&m->instance,&trap);free(ext);wasm_importtype_vec_delete(&imports);
 if(e||trap){*error=errtext(e,trap);sc_module_close(m);return NULL;}return m;
}
void sc_module_set_input(sc_module *m,const char *input){free(m->compiler_input);m->compiler_input=strdup(input);}
int sc_module_run(sc_module *m,int invoke,char **value,char **output,char **error){
 m->len=0;if(m->out)m->out[0]=0;wasmtime_val_t result;
 if(!call(m,invoke?"call0":"main",invoke?&m->closure:NULL,invoke?1:0,&result,1,error)){*output=strdup(m->out?m->out:"");return 0;}
 *output=strdup(m->out?m->out:"");m->len=0;if(m->out)m->out[0]=0;
 if(!invoke){if(m->kept)wasmtime_val_unroot(&m->closure);wasmtime_val_clone(&result,&m->closure);m->kept=1;}
 if(!call(m,"write",&result,1,NULL,0,error)){wasmtime_val_unroot(&result);return 0;}
 wasmtime_val_unroot(&result);*value=strdup(m->out?m->out:"");return 1;
}
void sc_module_close(sc_module *m){if(!m)return;if(m->kept)wasmtime_val_unroot(&m->closure);clear_entries(&m->symbols);while(m->tables){table *t=m->tables;m->tables=t->next;clear_entries(&t->items);wasmtime_val_unroot(&t->object);free(t);}if(m->module)wasmtime_module_delete(m->module);if(m->store)wasmtime_store_delete(m->store);free(m->out);free(m->number);free(m->compiler_input);free(m);}

void sc_module_set_ccall(sc_module *m,sc_ccall_fn fn,void *user){m->ccall=fn;m->ccall_user=user;}

unsigned char *sc_module_memory(sc_module *m,size_t *size)
{
 if(!m->has_memory){
  if(size)
   *size=0;
  return NULL;
 }
 if(size)
  *size=wasmtime_memory_data_size(m->ctx,&m->memory);
 return wasmtime_memory_data(m->ctx,&m->memory);
}

int sc_module_reserve(sc_module *m,size_t bytes)
{
 if(!m->has_memory)
  return 0;
 size_t have=wasmtime_memory_data_size(m->ctx,&m->memory);
 if(bytes<=have)
  return 1;
 uint64_t prev,pages=(bytes-have+65535)/65536;
 wasmtime_error_t *e=wasmtime_memory_grow(m->ctx,&m->memory,pages,&prev);
 if(e){
  wasmtime_error_delete(e);
  return 0;
 }
 return 1;
}

int sc_module_call3(sc_module *m,int a,int b,int c,int *result,char **error)
{
 if(!m->kept){*error=strdup("The program has not run yet");return 0;}
 wasmtime_val_t args[4]={m->closure,refint(m,a),refint(m,b),refint(m,c)},r;
 int32_t v=0,ok=1;
 if(!m->has_call3){
  wasmtime_extern_t fn;
  if(!wasmtime_instance_export_get(m->ctx,&m->instance,"call3",5,&fn)||fn.kind!=WASMTIME_EXTERN_FUNC){*error=strdup("The program exports no call3");return 0;}
  m->call3=fn.of.func;m->has_call3=1;
 }
 {
  wasm_trap_t *trap=NULL;
  wasmtime_error_t *e=wasmtime_func_call(m->ctx,&m->call3,args,4,&r,1,&trap);
  if(e||trap){*error=errtext(e,trap);ok=0;}
 }
 for(int k=1;k<4;k++)
  wasmtime_val_unroot(&args[k]);
 if(!ok)
  return 0;
 if(r.kind!=WASMTIME_ANYREF||!wasmtime_anyref_i31_get_s(m->ctx,&r.of.anyref,&v)){
  wasmtime_val_unroot(&r);
  *error=strdup("The program did not answer with a number");
  return 0;
 }
 wasmtime_val_unroot(&r);
 *result=v;
 return 1;
}
