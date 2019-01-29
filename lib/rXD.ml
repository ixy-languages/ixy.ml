open Log

[@@@ocaml.warning "-32"]

type t = Cstruct.t

[%%cstruct
  type adv_rxd_read = {
    pkt_addr : uint64;
    hdr_addr : uint64
  } [@@little_endian]
]

[%%cstruct
  type adv_rxd_wb = {
    pkt_info : uint16;
    hdr_info : uint16;
    ip_id : uint16;
    csum : uint16;
    status : uint16; (* Cstruct.uint16 is unboxed and therefore faster *)
    error : uint16;
    length : uint16;
    vlan : uint16
  } [@@little_endian]
]

let () = assert (sizeof_adv_rxd_wb = sizeof_adv_rxd_read)

let sizeof = sizeof_adv_rxd_wb

let dd t =
  let status = get_adv_rxd_wb_status t in
  let stat_dd, stat_eop = 0b01, 0b10 in
  match status land (stat_dd lor stat_eop) with
  | 0b11 -> true
  | 0b01 -> error "jumbo frames are not supported"
  | _ -> false

let size t = get_adv_rxd_wb_length t

let split num cs =
  let len = Cstruct.len cs in
  if num * sizeof > len then
    error "cstruct is too small (%d bytes) for %d descriptors" len num;
  Array.init
    num
    (fun i -> Cstruct.sub cs (i * sizeof) sizeof)

let reset cs Memory.{ phys; _ } =
  set_adv_rxd_read_pkt_addr cs phys;
  set_adv_rxd_read_hdr_addr cs 0L
