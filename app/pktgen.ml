open Core

let packet_size = 60

let batch_size = 64

[%%cstruct
  type ethernet = {
    dst : uint8 [@len 6];
    src : uint8 [@len 6];
    ethertype : uint16
  } [@@big_endian]
]

[%%cstruct
  type ipv4 = {
    version_ihl : uint8;
    tos : uint8;
    len : uint16;
    id : uint16;
    off : uint16;
    ttl : uint8;
    proto : uint8;
    csum : uint16;
    src : uint8 [@len 4];
    dst : uint8 [@len 4];
  } [@@big_endian]
]

[%%cstruct
  type udp = {
    src : uint16;
    dst : uint16;
    len : uint16;
    csum : uint16
  } [@@big_endian]
]

let pkt_data =
  let calc_ip_checksum buf =
    let ipv4 = Cstruct.sub buf sizeof_ethernet sizeof_ipv4 in
    let iter =
      Cstruct.iter
        (fun cs -> if Cstruct.len cs > 0 then Some 2 else None)
        (fun cs -> Cstruct.BE.get_uint16 cs 0)
        ipv4 in
    let sum = Cstruct.fold ( + ) iter 0 in
    let carry = (sum land 0xf0000) lsr 16 in
    (lnot ((sum land 0xffff) + carry)) land 0xffff in
  let buf = Cstruct.create packet_size in
  set_ethernet_dst "\x01\x02\x03\x04\x05\x06" 0 buf;
  set_ethernet_src "\x11\x12\x13\x14\x15\x16" 0 buf;
  set_ethernet_ethertype buf 0x8000;
  let ipv4 = Cstruct.shift buf sizeof_ethernet in
  set_ipv4_version_ihl ipv4 0x45;
  set_ipv4_tos ipv4 0x00;
  set_ipv4_len ipv4 (packet_size - sizeof_ethernet);
  set_ipv4_id ipv4 0x00;
  set_ipv4_off ipv4 0x00;
  set_ipv4_ttl ipv4 64;
  set_ipv4_proto ipv4 0x11;
  (* Cstruct.create zero-fills the buffer; no need to clear csum *)
  set_ipv4_src "\x0a\x00\x00\x01" 0 buf;
  set_ipv4_dst "\x0a\x00\x00\x02" 0 buf;
  set_ipv4_csum ipv4 (calc_ip_checksum buf);
  let udp = Cstruct.shift ipv4 sizeof_ipv4 in
  set_udp_src udp 42;
  set_udp_dst udp 1337;
  set_udp_len udp (packet_size - sizeof_ethernet - sizeof_ipv4);
  set_udp_csum udp 0;
  let payload = Cstruct.shift udp sizeof_udp in
  Cstruct.blit_from_string "ixy" 0 payload 0 3;
  buf (* rest of the payload is zero-filled *)

let usage () =
  Ixy.Log.error "Usage: %s <pci_addr>" Sys.argv.(0)

let () =
  if Array.length Sys.argv <> 2 then
    usage ();
  let pci_addr =
    match Ixy.PCI.of_string Sys.argv.(1) with
    | None -> usage ()
    | Some pci -> pci in
  let dev = Ixy.create ~pci_addr ~rxq:0 ~txq:1 in
  let mempool =
    Ixy.Memory.allocate_mempool
      ~pre_fill:pkt_data
      ~num_entries:2048 in
  let seq_num = ref 0l in
  while true do
    let bufs =
      Ixy.Memory.pkt_buf_alloc_batch mempool ~num_bufs:batch_size in
    Array.iter
      bufs
      ~f:(fun Ixy.Memory.{ data; _ } ->
          Cstruct.BE.set_uint32 data (packet_size - 4) !seq_num;
          Int32.incr seq_num);
    Ixy.tx_batch_busy_wait ~clean_large:false dev 0 bufs;
  done
