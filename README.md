# ixy.ml

ixy.ml is an OCaml rewrite of the [ixy](https://github.com/emmericp/ixy) userspace network driver.
It is designed to be readable, idiomatic OCaml code.
It supports Intel 82599 10GbE NICs (`ixgbe` family).
ixy.ml is still work-in-progress.

## Features

* multiple receive and transmit queues
* simple API

## Build instructions

Use `opam` to install the library:

```
opam pin add ixy git://github.com/ixy-languages/ixy.ml.git
```

Alternatively build manually:

```
make
make install
```

You will need `core`, `cstruct-unix`, `ppx_cstruct` and `ppx_deriving`. Install using:

```
opam install core cstruct-unix ppx_cstruct ppx_deriving
```

## Usage

### Library

`lib/ixy.mli` defines ixy.ml's public API.

## Internals

`lib/ixy.ml` contains the core logic.

## License

ixy.ml is licensed under the LGPL Version 3.0.

## Disclaimer

ixy.ml is not production-ready.
Do not use it in critical environments.
DMA may corrupt memory.

## Other languages

Check out the [other ixy implementations](https://github.com/ixy-languages).
