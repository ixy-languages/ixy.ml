# ixy.ml

ixy.ml is an [OCaml](https://ocaml.org) rewrite of the [ixy](https://github.com/emmericp/ixy) userspace network driver.
It is designed to be readable, idiomatic OCaml code.
It supports Intel 82599 10GbE NICs (`ixgbe` family).
ixy.ml is still work-in-progress.

## Quick start (on Debian)

```
sudo ./build.sh
sudo ./setup-hugetlbfs.sh
lspci | grep 'Ethernet controller.*\(82599ES\|X5[245]0\)'
sudo ixy-pktgen <PCI address of the controller you want to use>
```

## Features

* multiple receive and transmit queues
* multiple memory pools
* simple API
* interactive development in `ocaml`/`utop`

## Further Reading

* [**Driver Internals**](./doc/memory.md)
* [**OCaml Internals**](./doc/ocaml_internals.md)
* [**How-to-OCaml**](./doc/ocaml_basics.md)
* [**Intel 82599 Datasheet**](https://www.intel.com/content/dam/www/public/us/en/documents/datasheets/82599-10-gbe-controller-datasheet.pdf)
* [**ixy in other languages**](https://github.com/ixy-languages/ixy-languages)

## Documentation

### API Documentation

API documentation is built using [`odoc`](https://github.com/ocaml/odoc):

```
opam install odoc
```

Build the API documentation using:

```
make docs
```

The HTML documentation pages will be in `_build/default/_doc/_html/`.

You can also just read the documentation comments (enclosed in `(**` and `*)`) in the `lib/*.mli` files.

### Internals

ixy.ml communicates with the network card using memory-mapped I/O and DMA.
The DMA interface is documented in [`doc/memory.md`](./doc/memory.md).

### Help, I don't know OCaml!

There's a basic guide to OCaml in [`doc/ocaml_basics.md`](./doc/ocaml_basics.md).
It should help with reading the driver, though you won't be able to write your own OCaml programs after reading it.

ixy.ml also calls a few C functions ([`lib/memory.c`](./lib/memory.c) and [`lib/uname.c`](./lib/uname.c)).
[`doc/ocaml_internals.md`](./doc/ocaml_internals.md) explains a bit about the memory representation of OCaml values and how to interface with C.

## Build instructions

### Dependencies

You will need [`core`](https://github.com/janestreet/core) and [`ppx_cstruct`](https://github.com/mirage/ocaml-cstruct):

```
opam install core ppx_cstruct
```

### Building and Installing

Use `opam` to install the library:

```
opam pin add ixy git://github.com/ixy-languages/ixy.ml.git
```

Alternatively build manually:

```
make
```

This will build the driver and the three example apps.
The app binaries will be located in `_build/default/app/`.

```
make install
```

This will install the `ixy` library as well as the three example apps [`ixy-echo`](#ixy-echo), [`ixy-fwd`](#ixy-fwd) and [`ixy-pktgen`](#ixy-pktgen).

### Building the `test` programs

Build the test programs using:

```
make test
```

The program binaries will be located in `_build/default/test/`.

You can also just build a specific test program, e.g. build `check_nic.exe` using:

```
make check_nic
```

## Usage

### Example apps

Three example apps are provided in the [`app/`](./app/) directory.
In all examples a `<pci_addr>` is a PCI address such as `0000:ab:cd.e`.
ixy.ml has a [tolerant PCI address parser](./lib/pCI_addr.mll) that will automatically add punctuation, ignore wrong punctuation (`.` vs. `:`) and possibly add the default `0000` domain, e.g. `0000:ab:cd.e` can be written as `abcde` or `0000.ab.cd.e`.

#### [`ixy-echo`](./app/echo.ml)

`ixy-echo` retransmits all packets it receives.

Usage:

```
ixy-echo <pci_addr>
```

`ixy-echo` will create a single receive queue and a single transmit queue on the device specified by `<pci_addr>` and forward all packets received on the receive queue onto the transmit queue.

#### [`ixy-fwd`](./app/fwd.ml)

`ixy-fwd` is a bidirectional layer 2 forwarder.

Usage:

```
ixy-fwd <pci_addr> <pci_addr>
```

`ixy-fwd` will create a single receive queue and a single transmit queue on each device specified by the `<pci_addr>`s and forward all packets received on on device's receive queue onto the other device's transmit queue.

#### [`ixy-pktgen`](./app/pktgen.ml)

`ixy-pktgen` is a simple packet generator.

Usage:

```
ixy-pktgen <pci_addr>
```

`ixy-pktgen` will create a single transmit queue on the device specified by `<pci_addr>` and transmit the same 60 byte packet repeatedly as fast as possible.
The final 4 bytes of each packet are tagged with a 32-bit sequence number.

### Writing your own apps

Read the [API Documentation](#api-documentation).

Quick guide:

```ocaml
let () =
  (* parse a PCI address *)
  let pci_addr =
    match Ixy.PCI.of_string "0000:ab:cd.e" with
    | Some addr -> addr
    | None -> print_endline "couldn't parse address"; exit 1 in

  (* initialize a device *)
  let dev = Ixy.create ~pci_addr ~rxq:1 ~txq:1 in

  (* create a mempool *)
  let mempool = Ixy.Memory.allocate_mempool ~num_entries:2048 in

  (* allocate a packet *)
  let packet =
    match Ixy.Memory.pkt_buf_alloc mempool with
    | Some buf -> buf
    | None -> print_endline "couldn't allocate packet"; exit 1 in

  (* write some data to the packet *)
  Cstruct.memset packet.data 42;

  (* set the packet length *)
  packet.size <- 100;

  (* transmit the packet *)
  Ixy.tx_batch_busy_wait dev 0 [|packet|]
```

### Use interactively

Make sure you have [`findlib`](http://projects.camlcity.org/projects/findlib.html) installed, otherwise `#require` won't work.

In `ocaml`/`utop` do:

```ocaml
(* load ixy.ml *)
# #require "ixy";;
(* play around with ixy.ml *)
# Ixy.create;;
- : pci_addr:Ixy.PCI.t -> rxq:int -> txq:int -> Ixy.t
```

Be careful when accessing registers via the [`IXGBE`](./lib/ixgbe.ml) module; the NIC has DMA access and can write basically anywhere in physical memory.

## System requirements

* x86_64

Other 64-bit architectures supported by OCaml may also work, but haven't been tested.

* Linux

The driver will build on all operating systems supported by OCaml but requires Linux's `hugetlbfs` and `sysfs` to work.

* Intel 82599ES/X520/X540/X550

All NICs supported by ixy should work with ixy.ml, though only 82599ES and X540 NICs have been tested.

On unsupported system configurations the driver will print an error message and exit at runtime.

## Project Structure

The ixy.ml project is structured as follows:

* [`lib/`](./lib/) - the main ixy.ml driver
* [`app/`](./app/) - example programs that use ixy.ml
* [`test/`](./test/) - simple programs for debugging/testing internal functionality
* [`build.sh`](./build.sh) - script to build and install ixy.ml on a clean Debian system
* [`setup-hugetlbfs.sh`](./setup-hugetlbfs.sh) - script to mount a [`hugetlbfs`](https://www.kernel.org/doc/html/latest/admin-guide/mm/hugetlbpage.html) at `/mnt/huge` and allocate 512 huge pages

## License

ixy.ml is licensed under the terms of the [LGPL Version 3.0](https://www.gnu.org/licenses/lgpl-3.0.en.html) (see [`LICENSE`](./LICENSE)).

## Disclaimer

ixy.ml is not production-ready.
Do not use in critical environments.
DMA may corrupt memory.

## Other languages

ixy has also been written in other languages.
Check out the [other ixy implementations](https://github.com/ixy-languages/ixy-languages).
