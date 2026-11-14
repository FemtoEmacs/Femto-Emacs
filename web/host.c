/* Browser implementation of the same sc_module API used by Wasmtime.
 * C owns its mailbox copy. JS copies it at each boundary, before any
 * nested call; no interpreter fallback after a compiled operation fails. */
#include <emscripten.h>
#include <stdlib.h>
#include <string.h>
#include "../schemer/native-host.h"
struct sc_module { int id; unsigned char *memory; size_t size; sc_ccall_fn call; void *user; sc_editor_fn editor; void *editor_user; };
static sc_module *modules[128];
EM_ASYNC_JS(int, js_open, (const unsigned char *p, size_t n, int id), {
 try { await ChezwebScheme.open(HEAPU8.slice(p,p+n),id); return 1; }
 catch(e) { ChezwebScheme.error=String(e.message||e); return 0; }
});
EM_ASYNC_JS(int, js_run, (int id, int invoke), { return await ChezwebScheme.run(id,invoke); });
EM_ASYNC_JS(int, js_call, (int id,int a,int b,int c,int *result), {
 try { var n=await ChezwebScheme.call(id,a,b,c); HEAP32[result>>2]=n; return 1; }
 catch(e) { ChezwebScheme.error=ChezwebScheme.diagnostic(id,e); return 0; }
});
EM_JS(char *, js_text, (int id,int kind), {
 var s=kind===0?ChezwebScheme.error:kind===1?ChezwebScheme.modules.get(id).valueText:ChezwebScheme.modules.get(id).output;
 return stringToNewUTF8(s||'');
});
EM_JS(void, js_close, (int id), { ChezwebScheme.modules.delete(id); });
EM_JS(void, js_grow, (int id,size_t n), { var m=ChezwebScheme.modules.get(id).memory;if(m.buffer.byteLength<n)m.grow(Math.ceil((n-m.buffer.byteLength)/65536)); });
EMSCRIPTEN_KEEPALIVE unsigned char *web_module_buffer(int id) { return modules[id]->memory; }
EMSCRIPTEN_KEEPALIVE size_t web_module_size(int id) { return modules[id]->size; }
EMSCRIPTEN_KEEPALIVE char *web_editor_request(int id,const char *text){sc_module *m=modules[id];return m->editor?m->editor(text,m->editor_user):strdup("error No editor callback");}
EMSCRIPTEN_KEEPALIVE int web_ccall(int id,int n) { sc_module *m=modules[id];return m->call?m->call(m,n,m->user):1; }
sc_module *sc_module_open_code(const unsigned char *p,size_t n,const char *code,sc_editor_fn fn,void *user,char **error) {
 (void)code;int id;for(id=1;id<128&&modules[id];id++);if(id==128){*error=strdup("Too many Scheme modules");return NULL;}
 sc_module *m=calloc(1,sizeof *m);m->editor=fn;m->editor_user=user;m->id=id;m->size=1048576;m->memory=calloc(m->size,1);modules[id]=m;
 if(!js_open(p,n,id)){*error=js_text(id,0);sc_module_close(m);return NULL;}return m;
}
sc_module *sc_module_open(const unsigned char *p,size_t n,sc_editor_fn fn,void *u,char **e) {return sc_module_open_code(p,n,NULL,fn,u,e);}
void sc_module_close(sc_module *m){if(!m)return;js_close(m->id);modules[m->id]=NULL;free(m->memory);free(m);}
void sc_module_set_ccall(sc_module *m,sc_ccall_fn f,void *u){m->call=f;m->user=u;}
unsigned char *sc_module_memory(sc_module *m,size_t *n){*n=m->size;return m->memory;}
int sc_module_reserve(sc_module *m,size_t n){if(n>m->size){size_t size=(n+65535)&~(size_t)65535;unsigned char *p=realloc(m->memory,size);if(!p)return 0;memset(p+m->size,0,size-m->size);m->memory=p;m->size=size;js_grow(m->id,size);}return 1;}
int sc_module_run(sc_module *m,int invoke,char **value,char **out,char **error){int ok=js_run(m->id,invoke);*value=js_text(m->id,1);*out=js_text(m->id,2);if(!ok)*error=js_text(m->id,0);return ok;}
int sc_module_call3(sc_module *m,int a,int b,int c,int *r,char **e){int ok=js_call(m->id,a,b,c,r);if(!ok)*e=js_text(m->id,0);return ok;}
EM_JS(void,js_set_input,(int id,const char *s),{ChezwebScheme.modules.get(id).input=UTF8ToString(s);});
void sc_module_set_input(sc_module *m,const char *s){js_set_input(m->id,s);}
int sc_code_save(const unsigned char *p,size_t n,const char *path,char **e){(void)p;(void)n;(void)path;*e=strdup("Browser modules need no native machine-code cache");return 0;}
/* The fully compiled editor evaluates through its own hook. */
void compiled_init(void) {}
int compile_scripts(const char *dir,const char *log){(void)dir;(void)log;return 1;}

#include "header.h"
void web_relayout(void)
{
	relayout_windows();
}

/* everything drawn again (the core's update after a command) */
void web_redisplay(void)
{
	if (wheadp == NULL || curwp == NULL) return;
	mark_all_windows();
	update_display();
}
