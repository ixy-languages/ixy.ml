#include <sys/utsname.h>

#define CAML_NAME_SPACE

#include <caml/alloc.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/unixsupport.h>

CAMLprim value ixy_uname(value unit) {
    CAMLparam1(unit);
    CAMLlocal1(result);
    struct utsname name;
    if (uname(&name))
        uerror("uname", Nothing);
    result = caml_alloc(5, 0);
    Field(result, 0) = caml_copy_string(name.sysname);
    Field(result, 1) = caml_copy_string(name.nodename);
    Field(result, 2) = caml_copy_string(name.release);
    Field(result, 3) = caml_copy_string(name.version);
    Field(result, 4) = caml_copy_string(name.machine);
    CAMLreturn(result);
}
