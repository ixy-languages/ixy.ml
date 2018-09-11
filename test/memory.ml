open Core
open Ixy.Log

let () =
  let Ixy.Memory.{ virt; phys } = Ixy.Memory.allocate_dma 10 in
  let ocaml = Ixy.Memory.virt_to_phys virt in
  let c = Ixy.Memory.c_virt_to_phys virt in
  info "ocaml: %#018Lx\nc: %#018Lx\ndma: %#018Lx\n" ocaml c phys;
  if ocaml = c then
    info "addresses match"
  else
    error "addresses don't match";
  let dev = Ixy.create ~pci_addr:"0000:00:00.0" ~rxq:1 ~txq:1 in
  ignore dev;
  let num_entries = Ixy.(num_rx_queue_entries + num_tx_queue_entries) in
  let mempool =
    Ixy.Memory.allocate_mempool
      ~entry_size:2048
      ~num_entries in
  info
    "mempool has %d free bufs, expected: %d"
    (Ixy.Memory.num_free_bufs mempool)
    num_entries;
  let buf =
    match Ixy.Memory.pkt_buf_alloc mempool with
    | None -> error "couldn't allocate pkt_buf"
    | Some buf -> buf in
  Ixy.Memory.pkt_buf_dump_raw "pkt_buf-pre-resize" buf;
  let data = Ixy.Memory.pkt_buf_get_data buf in
  info "buf size: %d" (Bytes.length data);
  Ixy.Memory.pkt_buf_resize buf 10;
  info "buf size: %d" (Bytes.length data);
  Bytes.blit ~src:(Bytes.of_string "hallo") ~src_pos:0 ~dst:data ~dst_pos:0 ~len:5;
  Ixy.Memory.pkt_buf_dump_raw "pkt_buf-post-resize" buf;
  info
    "mempool has %d free bufs, expected: %d"
    (Ixy.Memory.num_free_bufs mempool)
    (num_entries - 1);
  Ixy.Memory.pkt_buf_free buf;
  info
    "mempool has %d free bufs, expected: %d"
    (Ixy.Memory.num_free_bufs mempool)
    num_entries
