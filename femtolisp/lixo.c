#include <stdlib.h>
#include <stdio.h>

int main () {
  char *this= getenv("HOME");
  char *buff= (char *)malloc(1000);
  sprintf(buff, "(load \"%s/init.lsp\")", this);
  printf("--%s--", buff);
  return 1;
}
