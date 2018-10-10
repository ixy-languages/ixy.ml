open Core
open Ixy.Log

let () =
  let dev = Ixy.create ~pci_addr:"0000:00:00.0" ~rxq:1 ~txq:1 in
  let rxq = dev.rxqs.(0) in
  let ring_size_bytes =
    rxq.num_entries * 16 in
  Ixy.Memory.dump_memory "rxd-ocaml" rxq.descriptors ring_size_bytes;
  Ixy.Memory.init_rxd rxq.descriptors rxq.virtual_addresses;
  Ixy.Memory.dump_memory "rxd-c" rxq.descriptors ring_size_bytes;
