#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <sys/stat.h>
#include "llt/llt.h"
#include "flisp.h"
#include "system.h"
extern void fe_set_completions(char *);
static value_t set_completions(value_t *args,uint32_t n) {
    argcount("fe-set-completions",n,1);
    fe_set_completions(tostring(args[0],"fe-set-completions"));return FL_T;
}
static value_t name_list(char **names, int count) {
    value_t result=FL_NIL, name=FL_NIL;fl_gc_handle(&result);fl_gc_handle(&name);
    for(int k=count-1;k>=0;k--){name=string_from_cstrn(names[k],strlen(names[k]));result=fl_cons(name,result);}
    fl_free_gc_handles(2);sys_free_names(names,count);return result;
}
static value_t files(value_t *args, uint32_t n) {
    argcount("directory-files", n, 1);
    int count;char **names=sys_directory_files(tostring(args[0],"directory-files"),&count);
    if(!names)lerror(IOError,"Cannot read directory");
    return name_list(names,count);
}
/* Preserve the typed directory prefix; expand ~/ only for filesystem access. */
static value_t file_completions(value_t *args, uint32_t n) {
    argcount("file-completions",n,1);
    int count;char **names=sys_file_completions(tostring(args[0],"file-completions"),&count);
    if(!names)return FL_NIL;
    return name_list(names,count);
}
void extra_init(void) {
    static builtinspec_t functions[]={{"directory-files",files},{"file-completions",file_completions},{"fe-set-completions",set_completions},{NULL,NULL}};
    assign_global_builtins(functions);
}
