#include "../schemer/native-host.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static char *editor(const char *s,void *p){(void)p;if(!strcmp(s,"(test-editor \"café\")"))return strdup("ok \"native café\"");return strdup("error Unexpected request");}
int main(int argc,char **argv){if(argc!=3)return 2;FILE *f=fopen(argv[1],"rb");if(!f)return 2;fseek(f,0,SEEK_END);long n=ftell(f);rewind(f);unsigned char *b=malloc(n);if(fread(b,1,n,f)!=(size_t)n)return 2;fclose(f);char *error=NULL,*value=NULL,*output=NULL;sc_module *m=sc_module_open(b,n,editor,NULL,&error);free(b);if(!m||!sc_module_run(m,0,&value,&output,&error)){if(!strcmp(argv[2],"--output"))printf("%sError: %s\n",output?output:"",error?error:"");else fprintf(stderr,"%s\n%s\n",output?output:"",error?error:"");sc_module_close(m);free(error);free(value);free(output);return 1;}int output_only=!strcmp(argv[2],"--output");if(output_only)printf("%s",output);else printf("%s%s\n",output,value);int code=output_only?0:(strcmp(value,argv[2])?1:0);free(error);free(value);free(output);sc_module_close(m);return code;}
