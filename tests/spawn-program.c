/* Exercise the actual detached exec path, not a mocked launcher. */
#include <stdio.h>
#include "system.h"
int main(int argc,char **argv){
 if(argc<2)return 2;
 const char *error=sys_spawn_program(argv[1],argv+2,argc-2);
 if(error){fprintf(stderr,"%s\n",error);return 1;}
 return 0;
}
