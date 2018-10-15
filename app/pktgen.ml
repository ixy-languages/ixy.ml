open Core

let packet_size = 60

let batch_size = 64

let packet_data =
  let calc_ip_checksum data =
    let cksum =
      String.fold
        data
        ~init:0
        ~f:(fun acc c ->
            let x = acc + Char.to_int c in
            if x > 0xffff then (x land 0xffff) + 1 else x)
      |> (lnot) in
    sprintf
      "%c%c"
      (Char.of_int_exn @@ cksum lsr 8)
      (Char.of_int_exn @@ cksum land 0xff) in
  let dst_mac = "\x01\x02\x03\x04\x05\x06" in
  let src_mac = "\x11\x12\x13\x14\x15\x16" in
  let ethertype = "\x08\x00" in
  let version_ihl_tos = "\x45\x00" in
  let ip_len =
    let hi = Char.of_int_exn @@ packet_size - 14 lsr 8 in
    let lo = Char.of_int_exn @@ packet_size - 14 land 0xff in
    sprintf "%c%c" hi lo in
  let id_flags_fragmentation = "\x00\x00\x00\x00" in
  let ttl = "\x40" in
  let proto = "\x11" in
  let ip_cksum = "\x00\x00" in (* TODO calc checksum *)
  let src_ip = "\x0a\x00\x00\x01" in
  let dst_ip = "\x0a\x00\x00\x02" in
  let src_port = "\x00\x2a" in
  let dst_port = "\x05\x39" in
  let udp_len =
    let hi = Char.of_int_exn @@ packet_size - 20 lsr 8 in
    let lo = Char.of_int_exn @@ packet_size - 20 land 0xff in
    sprintf "%c%c" hi lo in
  let udp_cksum = "\x00\x00" in
  let payload = "ixy" in
  let data =
    String.concat
      [ dst_mac;
        src_mac;
        ethertype;
        version_ihl_tos;
        ip_len;
        id_flags_fragmentation;
        ttl;
        proto;
        ip_cksum;
        src_ip;
        dst_ip;
        src_port;
        dst_port;
        udp_len;
        udp_cksum;
        payload
      ] in
  let checksum = Bytes.of_string @@ calc_ip_checksum data in
  let data = Bytes.of_string data in
  Bytes.blit ~src:checksum ~src_pos:0 ~dst:data ~dst_pos:24 ~len:2;
  data

let () =
  if Array.length Sys.argv <> 2 then
    Ixy.Log.error "Usage: %s <pci_addr>" Sys.argv.(0);
  let dev = Ixy.create ~pci_addr:Sys.argv.(1) ~rxq:0 ~txq:1 in
  let num_bufs = 2048 in
  let mempool = Ixy.Memory.allocate_mempool ~entry_size:2048 ~num_entries:num_bufs in
  let packets = Ixy.Memory.pkt_buf_alloc_batch mempool ~num_bufs in
  if Array.length packets <> num_bufs then
    Ixy.Log.error "could not allocate %d packet buffers" num_bufs;
  Array.iter packets ~f:(fun pkt_buf ->
      Ixy.Memory.pkt_buf_resize pkt_buf packet_size;
      Bytes.blit
        ~src:packet_data
        ~src_pos:0
        ~len:(Bytes.length packet_data)
        ~dst:(Ixy.Memory.pkt_buf_get_data pkt_buf)
        ~dst_pos:0
    );
  Array.iter packets ~f:Ixy.Memory.pkt_buf_free;
  while true do
    let packets =
      Array.to_list @@ Ixy.Memory.pkt_buf_alloc_batch mempool ~num_bufs:batch_size in
    let rec loop tx =
      match Ixy.tx_batch dev 0 tx with
      | [] -> ()
      | rest -> loop rest in
    loop packets
  done

