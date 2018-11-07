# OCaml Basics

This serves as a simple introduction to OCaml.
It was initially written during the summer of 2018; all code examples were tested in OCaml 4.07.0, though any somewhat recent version of OCaml should suffice.
The target audience is beginner to intermediate programmers with experience in at least one language; no functional programming experience is required.

Type annotations are rarely necessary and, unless specified otherwise, are just for readability.

## Tools

Tools that don't link to an external site are part of the standard OCaml distribution.

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

Comments are enclosed in `(*` and `*)`.
There are no single line comments.
Comments starting with `(**` are documentation comments that will be picked up by documentation generators.

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

In OCaml and many other functional languages, functions can be partially applied.
A partial application returns a function that accepts the initially missing parameters.

For example our `add : int -> int -> int` function returns the sum of two integers.
If we provide one of the two parameters, we get a function that returns the sum of this integer (in this example `2`) and another integer.

```ocaml
let add2 : int -> int = add 2
```

### Function definition with named and optional parameters

OCaml supports both named and optional function parameters.
Named parameters are prefixed with `~` and can be given in any order as long as the label is also given.

Optional parameters can either have a default value or be of type `'a option`.

```ocaml
let rec apply_n_times ~n ~f x =
  if n < 1 then
    x
  else
    apply_n_times ~n:(n - 1) ~f (f x)
```

### Lambda

Functions don't have to be have names; they can be constructed as lambdas (also called function literal, anonymous function).

```ocaml
fun x -> x + 1 (* function that maps each integer to its successor *)
```

### Boolean Operators

* `not` is the negation operator
* `&&` is the logical and operator
* `||` is the logical or operator

### `if` statement

`if` statements are actually expressions.

```ocaml
if 3 > 4 then
  7
else
  8
```

### `while` and `for` loops

```ocaml
let counter = ref 10 in
while !counter > 0 do (* '!' is the dereference operator, not the negation operator *)
  print_endline "still looping...";
  counter := !counter - 1 (* could write 'decr counter' instead *)
done

for i = 0 to 10 do (* both bounds are inclusive, i.e. i ∊ [0, 10] *)
  print_int i;
  print_newline ()
done

for i = 10 downto 0 do
  print_int i;
  print_newline ()
done
```

### Pattern matching

Pattern matching is used to deconstruct composite values.
Patterns are commonly found in `match <expr> with <pattern> -> <expr>`, `function <pattern> -> <expr>` and as the left-hand-side of a `let`-binding.

```ocaml
let f v =
  match v with
  | [1; x; 2] -> x (* match lists with three elements, starting with 1 and ending with 2 *)
  | [] -> 0 (* match empty list *)
  | 7 :: _ -> 11 (* match any list starting with a 7 *)
  | (35 as thirtyfive) :: _ -> thirtyfive (* introduce a label thirtyfive *)
  | hd :: _ when hd mod 2 = 0 -> hd (* pattern with guard *)
  | 11 :: 17 :: _ | 1 :: _ -> 100 (* match two different patterns *)
  | _ -> 10 (* wildcard pattern that matches any value *)

let g (a, b) = a + b (* deconstruct a tuple *)

let h = function (* decide between two variants *)
  | None -> 0
  | Some i -> i
```

### Lambda with pattern matching

```ocaml
function
| [] -> 0
| hd :: tl -> hd
```

### Polymorphism

`'a` (pronounced alpha) indicates a polymorphic type, similar to `<T>` in Java.

```ocaml
let rec len list = (* rec indicates that this function is recursive *)
  match list with
  | [] -> 0
  | hd :: tl -> 1 + len tl
```
`len` has type `'a list -> int`.

### Tail recursion

Tail recursion can be used to prevent stack overflows due to looping recursion.
When all recursive calls of a functions are "last calls" (i.e. there are no calculations done after the recursive call returns) the current call's stack frame can be reused for the recursive call.

The `len` function from the previous section can be optimized like so:

```ocaml
let len list =
  let rec aux acc l =
    match l with
    | [] -> acc
    | _ :: tl -> aux (acc + 1) tl in
  aux 0 list
```

### Main function

Unlike most programming languages OCaml has no `main` function.
Instead each OCaml compilation unit (each file) is evaluated and executed from top to bottom.
The order in which compilation units are executed is the same order in which they were linked.
Usually programmers will write no top-level statements besides a single `let` binding that binds to nothing and simply calls a function that serves as a main entrypoint, like so:
```ocaml
let main () =
  print_endline "Hello, world!"

let _ =
  main () (* just call main with argument () and ignore the result *)
```

`let _ = <something>` simply evaluates `<something>` and ignores the result.
Since an executable program works via its side-effects there is no information returned from the entrypoint.
This leads to a common pattern being `let () = <something>` which during compilation checks that `<something>` evaluates to the type `unit` whose only value is `()`.
This prevents programs whose entrypoints return some value from compiling, since returning some value is often caused by a forgotten function argument.
Consider the following example:
```ocaml
let main () =
  print_endline (* OH NO! we forgot the argument to print_endline *)

let () =
  main ()
```
This program will not compile since the type of `main ()` is `string -> unit` instead of `unit`.
This way the bug is caught during compilation.

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

### Functions

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


### Composite types

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
Unlike tuples they can have mutable members.

```ocaml
type my_record_t = {
  a : int;
  mutable b : float;
  c : string
}

let my_record : my_record_t = { a = 1; b = 3.1415; c = "this is a string" }

(* in-place update of mutable fields *)
my_record.b <- 2. *. my_record.b (* '+.', '-.', '*.' and '/.' are float operators *)

(* immutable update (copy) *)
let my_other_record : my_record_t = { my_record with a = 7; c = "also a string" }
```

Mutable references are actually implemented using mutable records:
```ocaml
type 'a ref = {
  mutable contents : 'a
}

let ref x = { contents = x }

let ( := ) r v = r.contents <- v

let ( ! ) r = r.contents
```

#### Variant

Variants are sum types (tagged unions) and consist of a number of different alternatives.
Each variant can optionally contain another type.
Variant names are called "constructors" and need to be capitalized.

```ocaml
type my_variant =
  | A
  | B of int
  | String of string

let my_variant_list = [B 1; String "this is also a string"; A; A] : my_variant list
```

#### Polymorphic variant

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

## Modules

OCaml programs and Libraries are usually subdivided into modules.
An OCaml source file `my_module.ml` gets compiled to a module `My_module`.
Note that the name automatically gets capitalized; every module name must start with a capital letter.

Please note that modules are much more powerful than the examples shown here; this serves only as an introduction.
Modules can be transformed to first class values, parameterized over other modules (such modules are known as `functor`s) and even inherit other modules' functionality (`include` keyword).

Modules can also contain other modules using the following syntax:
```ocaml
module My_module = struct
  type t = int

  let x = 1

  let y = 17
end
```

Module signatures look like this:
```ocaml
module My_module : sig
  type t = int

  val x : t

  val y : t
end
```

Modules signatures can be added to the module definition instead of or in addition to in `.mli` files:
```ocaml
module My_module : sig
  type t = int

  val x : t

  val y : t
end = struct
  type t = int

  let x = 1

  let y = 17
end
```

Module members can be accessed via standard dot-notation: `My_module.x`.

Module signatures are usually used to hide implementation details such as types or internally used utility functions.

### Example

The following program shows a simple implementation of complex arithmetic:
```ocaml
open Core

module Complex : sig
  type t

  val create : real:float -> imaginary:float -> t

  val to_string : t -> string

  val add : t -> t -> t

  val mul : t -> t -> t

  val conjugate : t -> t
end = struct
  type t = {
    real : float;
    imaginary : float
  }

  let create ~real ~imaginary =
    { real; imaginary }

  (* immediately deconstruct the argument *)
  let to_string { real; imaginary } =
    if not (Float.is_non_positive imaginary) then
      Printf.sprintf "%f + %fi" real imaginary
    else
      Printf.sprintf "%f - %fi" real (Float.neg imaginary)

  let add a b =
    { real = a.real +. b.real;
      imaginary = a.imaginary +. b.imaginary
    }

  let mul a b =
    let real =
      (a.real *. b.real) -. (a.imaginary *. b.imaginary) in
    let imaginary =
      (a.imaginary *. b.real) -. (a.real *. b.imaginary) in
    { real; imaginary }

  (* partial deconstruction and renaming in pattern matching *)
  let conjugate ({ imaginary; _ } as c) =
    { c with imaginary = Float.neg imaginary }
end

let () =
  let a = Complex.create ~real:10. ~imaginary:(-20.) in
  let b = Complex.create ~real:7. ~imaginary:0. in
  Printf.printf
    "a: %s\nb: %s\na + b: %s\na * b: %s\n"
    (Complex.to_string a)
    (Complex.to_string b)
    Complex.(to_string (add a b)) (* 'A.(<expr>)' opens module 'A' in <expr> *)
    Complex.(to_string (mul a b))
```

When run, the program produces this output:
```
a: 10.000000 - 20.000000i
b: 7.000000 + 0.000000i
a + b: 17.000000 - 20.000000i
a * b: 70.000000 - 140.000000i
```

Note that the internal implementation of the type `Complex.t` is hidden.
This obviously requires the constructor `Complex.create`, otherwise no values of type `Complex.t` could be created.

### Alternative example

The signature of the `Complex` module could also have been the following:
```ocaml
module Complex : sig
  type t = private {
    real : float;
    imaginary : float
  }

  val create : real:float -> imaginary:float -> t

  val to_string : t -> string

  val add : t -> t -> t

  val mul : t -> t -> t

  val conjugate : t -> t
end
```

Note the `private` keyword.
This prevents other modules from creating values of type `Complex.t`, though now they can deconstruct them (i.e. access the members `real` and `imaginary`) since their internal implementation is exposed.

## Objects and Classes

In addition to an extremely powerful module system OCaml also offers a somewhat unusual object and class system.
In fact, the "O" in "OCaml" stands for "Objective".

In reality the object system is rarely used; usually modules are the preferred abstraction method.

### Objects

Objects can be created without classes or any prior type definitions:
```ocaml
let x =
  object
    val x = 10

    method get_x = x
  end
```

Objects are enclosed in `object` and `end`.
Their instance variables are defined using `val` instead of `let`.
Methods are defined similar to functions, though unlike functions they are evaluated everytime they're called, therefore they don't require a `unit` argument.
Unlike most languages that use dot-notation to access methods, methods in OCaml are called using `#`.
Instance variables can optionally be defined as `mutable`.

Note that even though they appear in the object's type signature, instance variables are never visible outside the object; setters and getters are always required if access to instance variables is required.

Objects can optionally refer to themselves using a programmer-chosen name:
```ocaml
let x =
  object (self)
    val mutable x = 10

    method get_x = x

    method set_x new_x = x <- new_x

    method print_and_update new_x =
      Printf.printf "old x: %d\n" x;
      self#set_x new_x
  end
```

In this example the object could call its own methods using `self`; the equivalent in Java would be `this`.
By convention `self` is used, though any non-keyword can be used, e.g. `object (this) ... end` or `object (me) ... end` would also work.

Since there is no need for a constructor, if an object needs to perform some other initialization, the programmer can define a special `initializer` method that is called upon instantiation:
```ocaml
let x =
  object (self)
    val mutable x = 10

    method get_x = x

    method set_x new_x = x <- new_x

    method print_and_update new_x =
      Printf.printf "old x: %d\n" x;
      self#set_x new_x

    initializer
      Printf.printf "created object with x = %d\n" x
  end
```

### Classes

Classes can be thought of as functions returning objects, though they don't necessarily take arguments.

A basic class looks like this:
```ocaml
class my_class =
  object
    val x = 7

    method get_x = x
  end
```

Objects of this class can be instantiated using the `new` keyword:
```ocaml
let () =
  let my_object = new my_class in
  Printf.printf "my_object's x has the value %d\n" my_object#get_x
```

Let's write a basic integer container class:
```ocaml
class int_container i =
  object (self)
    val mutable content = i

    method get_int = content

    method set_int new_i = content <- new_i

    method twice =
      self#set_int (2 * self#get_int)
  end
```

Objects of this class start with an initial value given during construction and can be updated at any point:
```ocaml
let print_content container =
  Printf.printf "%d\n" container#get_int

let () =
  let container = new int_container 17 in
  print_content container;
  container#set_int 800;
  print_content container;
  container#twice;
  print_content container
```

### Inheritance

Let's demonstrate inheritance by creating a parameterized container class and then specializing it for our `int_container`:
```ocaml
(* the class 'container' is parameterized over the polymorphic type 'a *)
class ['a] container init =
  object
    (* explicit type annotation is necessary here, otherwise 'content' could have some other type 'b *)
    val mutable content : 'a = init

    method get_content = content

    method set_content new_content = content <- new_content
  end

class int_container init =
  object (self)
    inherit [int] container init

    method twice =
      self#set_content (2 * self#get_content)
  end

class string_container init =
  object (self)
    inherit [string] container init

    method length = (* pointless example method *)
      String.length self#get_content (* could also access instance variable content directly *)
  end
```

### Virtual classes

Classes that cannot be instantiated into objects and only exist to be inherited are usually called "abstract", in OCaml they are called `virtual`.

If we don't want instantiations of the `['a] container` class, we can make it `virtual`:

```ocaml
class virtual ['a] container init =
  object
    val mutable content : 'a = init

    method get_content = content

    method set_content new_content = content <- new_content
  end
```

`new container` will now fail:

```
Error: Cannot instantiate the virtual class container
```

### Virtual methods

`virtual` classes can have both actual implemented methods as well as `virtual` methods.
`virtual` methods must be implemented by classes that inherit them, unless they themselves are `virtual`.

In the following example our `container` class requires subclasses to define a methods for serialization:

```ocaml
class virtual ['a] container init =
  object (self)
    val mutable content : 'a = init

    method get_content = content

    method set_content new_content = content <- new_content

    method virtual serialize : string
  end

class int_container init =
  object (self)
    inherit [int] container init

    method twice =
      self#set_content (2 * self#get_content)

    method serialize =
      Int.to_string self#get_content
  end

class string_container init =
  object (self)
    inherit [string] container init

    method length =
      String.length self#get_content

    method serialize =
      self#get_content
  end
```

### Private methods

Methods marked with the `private` keyword can only be called by subclasses.

### Structural typing

Unlike all other values in OCaml (except modules and polymorphic variants), objects are structurally typed.
Roughly speaking, any object can be used in place of any other object as long as it supports this object's methods.

## Common practices

### Indentation

OCaml has no meaningful whitespace although several style guides ([1](https://ocaml.org/learn/tutorials/guidelines.html#Indentation-of-programs), [2](https://opensource.janestreet.com/standards/#indentation)) recommend indenting with two spaces.

### Type conversion

OCaml never implicitly casts one type to another. All conversion has to be done explicitly.

```ocaml
let i : int = 1
let f : float = float_of_int i (* a_of_b instead of b_to_a *)
```

Using Core:

```ocaml
open Core

let i : int = 1
let f : float = Float.of_int i
let f : float = Int.to_float i
```

### Modules

Just as any other language it is common practice to subdivide programs into small and easy-to-understand modules.

Oftentimes modules obviate the need for objects given that object functionality can be sufficiently emulated using modules.

Modules oftentimes define their own type (see the `Complex` module in the [**Modules**](#modules) section).
This central type of the module is by convention called `t`, accessed by other modules as `Module_name.t`, and instantiated using a `create` function.

### Function composition operators

OCaml's standard library contains the two operators `|>` and `@@` that implement reverse function application and function application, respectively:

```ocaml
let ( |> ) x f = f x

let ( @@ ) f x = f x
```

`|>` can be thought of as a pipeline operator (similar to the `|` operator commonly found in shell languages) that "pipes" the value on the left of the operator into the function on the right of the operator, e.g. `x |> f |> g` is equivalent to `g (f x)`.
This operator lends itself to chains of function application where each function's output is "piped" into the next function:

```ocaml
List.range 0 100 (* create the list [0; ...; 99] *)
|> List.filter ~f:(fun i -> i mod 2 = 0 || i >= 20) (* remove all odd values less than 20 *)
|> List.map ~f:(fun i -> i + i) (* double all values *)
|> List.fold ~init:0 ~f:( + ) (* sum the list *)
```

`@@` is simply a low-precedence operator that obviates the need for parentheses when applying a function to the result of another function application, e.g. `g @@ f x` is equivalent to `g (f x)`.
This operator can improve readability of long chains of nested function applications.

### ppx

OCaml supports syntax extensions via ppx preprocessors.
Source code can be annotated at certain spots.
These annotations are preserved in the first abstract syntax tree (AST) which in turn can be scanned and modified by ppx preprocessors.

OCaml includes a few syntax extensions, for example to control inlining behavior:

```ocaml
let f x = x + x [@@inline always] (* inline 'f' regardless of cost/benefit *)

let rec len = function
  | [] -> 0
  | _ :: tl -> 1 + len tl [@@unroll 10] (* unroll the loop 10 times *)
```

## Resources

### OCaml manual

[The OCaml manual](http://caml.inria.fr/pub/docs/manual-ocaml/) is the language reference. It details the language, the runtime, the foreign function interface and all language extensions.

### Real World OCaml

[Real World OCaml](https://v1.realworldocaml.org/) is a great book that explains all of the topics here in greater depth.
[The second edition](https://dev.realworldocaml.org/) is currently being written.
Both are available online for free.
