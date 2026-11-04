/* GUI-subsystem launcher: no extra console, and no shell interpolation. */
#include <unistd.h>
#include <stdio.h>
int main(int argc,char **argv) {
 char *args[argc+6];
 args[0]="/bin/bash";args[1]="--noprofile";args[2]="--norc";
 args[3]="/app/start.sh";args[4]="--gui";
 for(int i=1;i<argc;i++)args[i+4]=argv[i];
 args[argc+4]=NULL;
 execv(args[0],args);perror("Chezweb GUI");return 1;
}
