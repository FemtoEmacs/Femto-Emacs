/* Filesystem primitive: byte-exact snapshot, no source state mutation,
 * no overwrite without approval, and scoped destinations. Disposable HOME. */
#include "../src/header.h"
#include <sys/stat.h>
#include <unistd.h>
extern char *fe_install_script(char *,int);
static buffer_t buffer;
buffer_t *curbp=&buffer;
int main(int argc,char **argv)
{
 assert(argc==2);assert(!setenv("HOME",argv[1],1));
 unsigned char text[]="(define café 42)\n\0tail";
 unsigned char bytes[128];size_t n=sizeof text-1;
 memset(bytes,0xcc,sizeof bytes);memcpy(bytes,text,5);memcpy(bytes+21,text+5,n-5);
 memset(&buffer,0,sizeof buffer);buffer.b_buf=bytes;buffer.b_gap=bytes+5;
 buffer.b_egap=bytes+21;buffer.b_ebuf=bytes+21+n-5;
 buffer.b_point=3;buffer.b_mark=1;buffer.b_flags=B_MODIFIED;
 buffer_t before=buffer;unsigned char original[128];memcpy(original,bytes,sizeof bytes);
 assert(!*fe_install_script("sample.scm",0));
 char dest[4096];snprintf(dest,sizeof dest,"%s/.chezemax/users/sample.scm",argv[1]);
 FILE *f=fopen(dest,"rb");assert(f);unsigned char got[128];assert(fread(got,1,sizeof got,f)==n);fclose(f);assert(!memcmp(got,text,n));
 assert(!memcmp(&before,&buffer,sizeof buffer));assert(!memcmp(original,bytes,sizeof bytes));
 bytes[0]=';';assert(*fe_install_script("sample.scm",0));
 f=fopen(dest,"rb");assert(f);assert(fgetc(f)=='(');fclose(f);
 assert(!*fe_install_script("sample.scm",1));f=fopen(dest,"rb");assert(f);assert(fgetc(f)==';');fclose(f);
 assert(*fe_install_script("../outside.scm",1));assert(*fe_install_script(".hidden.scm",0));
 assert(*fe_install_script("not-scheme.txt",0));assert(*fe_install_script("nested/name.scm",0));
 assert(*fe_install_script("nested\\name.scm",0));
 char dir[4096];snprintf(dir,sizeof dir,"%s/.chezemax/users/folder.scm",argv[1]);assert(!mkdir(dir,0700));
 assert(*fe_install_script("folder.scm",1));
 puts("PASS script snapshot: exact UTF-8/NUL bytes, intact buffer state, approved overwrite and confined paths");
 return 0;
}
