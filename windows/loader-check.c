#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
int main(int argc,char **argv) {
 if(argc!=2)return 2;
 HMODULE dll=LoadLibraryA(argv[1]);
 if(!dll){DWORD code=GetLastError();char message[2048];
 FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM|FORMAT_MESSAGE_IGNORE_INSERTS,NULL,code,0,message,sizeof message,NULL);
 fprintf(stderr,"LoadLibrary: %lu: %s\n",(unsigned long)code,message);return 1;}
 puts("PASS native Windows Wasmtime DLL loads");FreeLibrary(dll);return 0;
}
