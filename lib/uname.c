#include <sys/utsname.h>

#define CAML_NAME_SPACE

#include <caml/alloc.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>

CAMLprim value caml_uname(value unit) {
    CAMLparam1(unit);
    struct utsname name;
    uname(&name);
    CAMLreturn(caml_copy_string(name.sysname));
}
