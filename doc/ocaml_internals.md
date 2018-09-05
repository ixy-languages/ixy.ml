# OCaml Internals

## Memory representation of values

OCaml values are always exactly one machine word in size (usually 32 or 64 bit).
An OCaml value (type `value` in C) is either a 31/63-bit integer (lowest bit set to 1), a pointer to the OCaml heap or a pointer to some other memory.

### Integer

A signed integer `n` is represented as `(n << 1) + 1`.
There are no unsigned integers.

### Variants (without members)

Variants without members are represented as OCaml integers. They are numbered starting from zero in the order they appear in in the type definition.

```ocaml
type my_type =
  | A (* represented as 0 *)
  | B of int (* represented as a block *)
  | X (* represented as 1 *)
  | Y (* represented as 2 *)
  | Z (* represented as 3 *)
```

### String

```ocaml
let bla = "ab"
```
is represented as
```
+---+---+---+---+
|hdr|'a'|'b'|pad|
+---+---+---+---+
      ^
      |
     bla
```

An OCaml string is a pointer to a block of memory containing the characters of the string.
The pointer points to the first character of the string.

To the "left" of the first character there is a header one word in size.
The header contains the size of the string as well as some metadata for the garbage collector.
The string is always padded to the next word with the number of padding bytes preceding the last padding byte stored in the last padding byte, all other padding bytes are null bytes.
The padding for the example string `bla` is `"\x00\x00\x00\x00\x00\x05"` since there are 5 padding bytes preceding the last padding byte.

OCaml strings can be passed to C functions, although they may contain null characters that will be interpreted as the end of the string by the standard C functions such as `strcmp()` or `strcpy()`.

### Composite values

Composite values (tuples, variants with members, records, arrays, etc.) are represented as pointers to blocks.
Boxed values (`int64`, `int32`, `float`, etc.) are also represented as blocks.
A block consists of a header as well as a number of "fields".
Both the header and each field are one word in size.

```ocaml
let x = 1L (* suffix L -> int64; l -> int32; n -> nativeint *)
```
is represented as such
```
+---+---+
|hdr| 1 |
+---+---+
      ^
      |
      x
```

## Foreign Function Interface

OCaml offers a foreign function interface (ffi) that allows OCaml programs to call C functions and vice versa. Fortran is also supported. This tutorial only covers calls from OCaml to C.

### Declaring a C function in OCaml

```ocaml
external add_int_and_float : int -> float -> float = "caml_add_int_and_float"
(* C functions that are called from OCaml are commonly prefixed with "caml_" *)
```

### Using a foreign function

Foreign functions are used exactly like standard OCaml functions. Partial application works.

```ocaml
let f : float = add_int_and_float 10 3.14
let add27 : float -> float = add_int_and_float 27
let f : float = add27 f (* shadowed variable *)
```

### Implementing OCaml-compatible C functions

```c
#define CAML_NAME_SPACE // prevent namespace collisions

#include <caml/memory.h> // CAMLreturn etc.
#include <caml/mlvalues.h> // conversion macros
#include <caml/alloc.h> // OCaml heap allocation

// CAMLprim - OCaml primitive
// value - type of OCaml values (integers/pointers)
CAMLprim value caml_add_int_and_float(value i, value f) {
    // GC needs to know about these values
    CAMLparam2(i, f);
    // Long_val() - conversion macro, read "long integer of value"
    // OCaml integers are actually long integers
    long c_long = Long_val(i);
    // Double_val() - conversion macro, read "double of value"
    double c_double = Double_val(f);
    // CAMLreturn instead of return
    // caml_copy_double() allocates a new float on the OCaml heap
    CAMLreturn(caml_copy_double(c_double + c_long));
}
```
