# OCaml Basics

This serves as a simple introduction to OCaml.

## Tools

* `ocaml` - OCaml interpreter (aka toplevel)
* `ocamlc` - OCaml bytecode compiler
* `ocamlrun` - OCaml bytecode interpreter
* `ocamlopt` - OCaml optimizing native code compiler
* [`opam`](https://github.com/ocaml/opam) - OCaml package manager
* [`utop`](https://github.com/diml/utop) - Interactive OCaml interpreter
* `ocamldoc`/[`odoc`](https://github.com/ocaml/odoc) - Documentation generators
* `ocamllex` - Lexer generator
* `ocamlyacc`/[`menhir`](http://gallium.inria.fr/~fpottier/menhir/) - Parser generators
* [`dune`](https://github.com/ocaml/dune) (formerly `jbuilder`) - Build system
* [`core`](https://github.com/janestreet/core/) - Alternative standard library
* [`merlin`](https://github.com/ocaml/merlin) - Text editor integration

## Syntax

### Statement separators

Statements in the OCaml interpreter have to be suffixed with `;;`. `;;` is not used in compiled OCaml code.

```ocaml
# let x = 1;;
val x : int = 1
# let y = 2 * x;;
val y : int = 2
```

### Comments

Comments are enclosed in `(*` and `*)`. There are no single line comments.

```ocaml
(* this is a comment *)
(* nested (* comments (* are *) (* handled (* correctly *) *) *) *)

val f : int -> bool
(** this is a documentation comment *)
```

### Type annotation

Type annotations are rarely needed; the compiler infers types automatically.

```ocaml
let x : int = 1 (* declare x to be of type int explicitly *)
```

### Function definition

```ocaml
let square x : int -> int = x * x

let add a b : int -> int -> int = a + b
```

### Function application

```ocaml
square 2
```

### Partial application

```ocaml
let add2 : int -> int = add 2
```

### Lambda

```ocaml
fun x -> x + 1 (* function that maps each integer to its successor *)
```

### Pattern matching

```ocaml
match v with
| [1; x; 2] -> x (* match lists with three elements, starting with 1 and ending with 2 *)
| [] -> 0 (* match empty list *)
| 7 :: _ -> 11 (* match any list starting with a 7 *)
| (35 as hd) :: _ -> hd (* introduce a label hd *)
| hd :: _ when hd mod 2 = 0 -> hd (* pattern with guard *)
| 11 :: 17 :: _
| 1 :: _ -> 100 (* match two different patterns *)
| _ -> 10 (* wildcard pattern that matches any value *)
```

### Lambda with pattern matching

```ocaml
function
| [] -> 0
| hd :: tl -> hd
```

### Polymorphy

`'a` (pronounced alpha) indicates a polymorphic type, similar to `<T>` in Java.

```ocaml
let rec len list = (* rec indicates that this function is recursive *)
  match list with
  | [] -> 0
  | hd :: tl -> 1 + len tl
```
`len` has type `'a list -> int`.

## Types

### Basic types

OCaml has a number of integrated basic types.
* `int` 63/31-bit signed integer
* `float` IEEE 754 double precision float
* `char` 8-bit character
* `bool` `true`/`false`
* `unit` empty value used instead of `void`
* `int64` boxed 64-bit signed integer
* `int32` boxed 32-bit signed integer
* `nativeint` boxed machine word size signed integer
* `string` immutable string
* `bytes` mutable string

### Complex types

#### Function

```ocaml
let add_3_values a b c = a + b + c
```
`add_3_values` has type `int -> int -> int -> int`.
This is actually `int -> (int -> (int -> int))` to allow partial application (currying).

```ocaml
let identity x = x
```
`identity` has type `'a -> 'a`.
This means `<any type> -> <the same type>`.

```ocaml
let ( %& ) a b = a + b

assert (1 %& 2 = 1 + 2) (* assertions are rarely used *)
```
Functions whose names are inside `(` and `)` and consist only of [these characters](http://caml.inria.fr/pub/docs/manual-ocaml/lex.html#sec83) are infix/prefix operators.  
In this case we defined our own `+` operator: `%&`.

#### Mutable reference

```ocaml
let x : int ref = ref 1 (* declare mutable value *)
x := 2 (* mutate *)
let y : int = !x (* dereference *)
```

#### Tuple

Tuples are a collection of values of possibly different types.

```ocaml
let my_tuple : int * float = (1, 2.) (* 2.0 can be written as 2. *)
```

#### List

Lists are a collection of values of the same type.
Lists are immutable and can be pattern matched.

```ocaml
let my_list : int list = [1; 2; 3]

match my_list with
| [] -> print_endline "empty list"
| hd :: tl -> print_endline "list with a head and a tail"
```

#### Array

Arrays are a collection of values of the same type.
They offer constant time random access but cannot be extended/shortened.
Arrays are mutable.

```ocaml
let my_array : int array = [|1; 2; 3|]

my_array.(2) <- 5 (* in-place update *)

match my_array with
| [|a; b; c|] -> print_endline "array with three elements"
| _ -> print_endline "array with any other number of elements"
```

#### String

```ocaml
let my_string = "hello, i am a string."

let third_character = my_string.[2] (* third_character = 'l' *)
```

#### Record

Records are similar to structs in C.
They are basically tuples with named members.

```ocaml
type my_record_t = {
  a : int;
  mutable b : float;
  c : string
}

let my_record : my_record_t = { a = 1; b = 3.1415; c = "this is a string" }
```

#### Variant

Variants are sum types (tagged unions) and consist of a number of different alternatives.
Each variant can optionally contain another type.

```ocaml
type my_variant =
  | A
  | B of int
  | String of string

let my_variant_list = [B 1; String "this is also a string"; A; A] : my_variant list
```

#### Polymorphic Variant

Polymorphic variants are variants that can be created without a type definition.

```ocaml
`B 1 : [> `B of int ]
`A : [> `A ]

[`X; `Y "some string"] : [> `X | `Y of string ] list
```

The `>` indicates that this variant type can also accept new variants.

#### Polymorphic type

```ocaml
type 'a list =
  | []
  | ( :: ) of 'a * 'a list
```
This is the actual definition of the list type in OCaml.
A list can contain values of any type (`'a`) but all values have to have the same type.

## Common practices

### Indentation

OCaml has no meaningful whitespace although [several](https://ocaml.org/learn/tutorials/guidelines.html#Indentation-of-programs) [style guides](https://opensource.janestreet.com/standards/#indentation) recommend indenting with two spaces.

### Type conversion

OCaml never implicitly casts one type to another. All conversion has to be done explicitly.

```ocaml
let i : int = 1
let f : float = float_of_int i (* a_of_b instead of b_to_a *)

open Core (* use alternative stdlib *)

(* creates new variables instead of changing the old ones (immutability by default)
   this practice is also called "shadowing" *)
let i : int = 1
let f : float = Float.of_int i
let f : float = Int.to_float i
```

## Memory representation of values

OCaml values are always exactly one machine word in size (usually 32 or 64 bit).
An OCaml value (type `value` in C) is either a 63-bit integer (lowest bit set to 1), a pointer to the OCaml heap or a pointer to some other memory.

### Integer

A signed integer `n` is represented as `(n << 1) + 1`.
There are no unsigned integers.

### Variants (without members)

Variants without members are represented as integers. They are numbered starting from zero in the order they appear in in the type definition.

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

OCaml strings can be passed to C functions, although they may contain null characters that will be interpreted as the end of the string by the standard C functions such as `strcmp` or `strcpy`.

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
|hdr|i64|
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

## Resources

### OCaml manual

[The OCaml manual](http://caml.inria.fr/pub/docs/manual-ocaml/) is the language reference. It details the language, the runtime, the ffi and all language extensions.

### Real World OCaml

[Real World OCaml](https://v1.realworldocaml.org/) is a great book that explains all of the topics here in greater depth.
[The second edition](https://dev.realworldocaml.org/) is currently being written.
Both are available online for free.
