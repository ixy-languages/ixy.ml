#include <unistd.h>
#include <inttypes.h>
#include <sys/mman.h>

#define CAML_NAME_SPACE

#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/unixsupport.h>
#include <caml/bigarray.h>

CAMLprim value ixy_pagesize(value v_unit) {
    CAMLparam1(v_unit);
    long pagesize = sysconf(_SC_PAGESIZE);
    if (pagesize == -1)
        uerror("sysconf", Nothing);
    return caml_copy_int64(pagesize);
}

CAMLprim value ixy_int64_of_addr(value v_buf, value v_off) {
    CAMLparam2(v_buf, v_off);
    CAMLlocal1(v_ptr);
    size_t offset = Long_val(v_off);
    v_ptr = caml_copy_int64((uint64_t) Caml_ba_data_val(v_buf) + offset);
    CAMLreturn(v_ptr);
}

CAMLprim value ixy_mlock(value v_buf, value v_off, value v_size) {
    CAMLparam3(v_buf, v_off, v_size);
    void *ptr = Caml_ba_data_val(v_buf);
    size_t offset = Long_val(v_off), size = Long_val(v_size);
    if (mlock(ptr, offset + size))
        uerror("mlock", Nothing);
    CAMLreturn(Val_unit);
}
