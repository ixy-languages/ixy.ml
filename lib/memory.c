#include <inttypes.h>
#include <sys/mman.h>

#define CAML_NAME_SPACE

#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/unixsupport.h>
#include <caml/bigarray.h>

CAMLprim value ixy_int64_of_addr(value cstruct) {
    CAMLparam1(cstruct);
    CAMLlocal1(ptr);
    uint64_t offset = Long_val(Field(cstruct, 1));
    ptr = caml_copy_int64(offset + (uint64_t) Caml_ba_data_val(Field(cstruct, 0)));
    CAMLreturn(ptr);
}

CAMLprim value ixy_mlock(value cstruct) {
    CAMLparam1(cstruct);
    void *ptr = Caml_ba_data_val(Field(cstruct, 0));
    if (mlock(ptr, Long_val(Field(cstruct, 2))))
        uerror("mlock", Nothing);
    CAMLreturn(Val_unit);
}
