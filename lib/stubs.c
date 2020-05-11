#include <stdint.h>

#define CAML_NAME_SPACE

#include <caml/alloc.h>
#include <caml/bigarray.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

CAMLprim value ixy_int64_of_addr(value v_buf, value v_off) {
    CAMLparam2(v_buf, v_off);
    CAMLlocal1(v_ptr);
    size_t offset = Long_val(v_off);
    v_ptr = caml_copy_int64((uint64_t) Caml_ba_data_val(v_buf) + offset);
    CAMLreturn(v_ptr);
}

CAMLprim value ixy_get_reg32(value v_buf, value v_reg) {
    CAMLparam2(v_buf, v_reg);
    __asm__ volatile("" : : : "memory");
    void *base = Caml_ba_data_val(v_buf);
    CAMLreturn(Val_long(*((volatile uint32_t *) (base + Long_val(v_reg)))));
}

CAMLprim value ixy_set_reg32(value v_buf, value v_reg, value v_data) {
    CAMLparam3(v_buf, v_reg, v_data);
    __asm__ volatile("" : : : "memory");
    void *base = Caml_ba_data_val(v_buf);
    *((volatile uint32_t *) (base + Long_val(v_reg))) = Long_val(v_data);
    CAMLreturn(Val_unit);
}
