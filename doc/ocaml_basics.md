# OCaml Basics

## Tools

* `ocaml` - OCaml interpreter
* `ocamlc` - OCaml bytecode compiler
* `ocamlrun` - OCaml bytecode interpreter
* `ocamlopt` - OCaml optimizing native code compiler
* `opam` - OCaml package manager
* `utop` - Interactive OCaml interpreter
* `ocamldoc`/`odoc` - Documentation generator
* `ocamllex` - Lexer generator
* `ocamlyacc`/`menhir` - Parser generators
* `dune` (formerly `jbuilder`) - Build system
* `core` - Alternative standard library

## Syntax

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
has type `'a list -> int`.

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
* `intnat` boxed machine word size signed integer
* `string` immutable string
* `bytes` mutable string

### Composite types

#### Tuple

Tuples are a collection of values of possibly different types.

```ocaml
let my_tuple : int * float = (1, 2.0)
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

#### Polymorphic Variants

Polymorphic variants are variants that can be created without a type definition.

```ocaml
`B 1 : [> `B of int ]
`A : [> `A ]

[`X; `Y "some string"] : [> `X | `Y of string ] list
```

The `>` indicates that this variant type can also accept new variants.

#### Polymorphic types

```ocaml
type 'a list =
  | []
  | ( :: ) of 'a * 'a list
```

## Memory representation of values

OCaml values are always exactly one machine word in size (usually 32 or 64 bit).
An OCaml value (type `value` in C) is either a 63-bit integer (lowest bit set to 1), a pointer to the OCaml heap or a pointer to some other memory.

### Integer

A signed integer `n` is represented as `(n << 1) + 1`.
There are no unsigned integers.

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
The string is always padded to the next word with the number of padding bytes stored in the last padding byte, all other padding bytes are null bytes.

OCaml strings can be passed to C functions, although they may contain null characters that will be interpreted as the end of the string by the standard C functions such as `strcmp` or `strcpy`.

### Composite values

Composite values (tuples, variants, records, arrays, etc.) are represented as pointers to blocks.
Boxed values (`int64`, `int32`, `float`, etc.) are also represented as blocks.
A block consists of a header as well as a number of "fields".
Both the header and each field are one word in size.

```ocaml
let x = 1L
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
