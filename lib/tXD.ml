open Log

[@@@ocaml.warning "-32"]

type t = Cstruct.t

[%%cstruct
  type adv_tx_read = {
    buffer_addr : uint64;
    cmd_type_len : uint32;
    olinfo_status : uint32
  } [@@little_endian]
]

[%%cstruct
  type adv_tx_wb = {
    rsvd : uint64;
    nxtseq_seed : uint32;
    status : uint32
  } [@@little_endian]
]

let () = assert (sizeof_adv_tx_wb = sizeof_adv_tx_read)

let sizeof = sizeof_adv_tx_wb

let dd t =
  let stat_dd = 0b1l in
  Int32.logand (get_adv_tx_wb_status t) stat_dd <> 0l

let split num cs =
  let len = Cstruct.len cs in
  if num * sizeof > len then
    error "cstruct is too small (%d bytes) for %d descriptors" len num;
  Array.init
    num
    (fun i -> Cstruct.sub cs (i * sizeof) sizeof)

let reset cs Memory.{ size; phys; _ } =
  set_adv_tx_read_buffer_addr cs phys;
  let const_part =
    let dcmd_eop = 0x01000000l in
    let dcmd_rs = 0x08000000l in
    let dcmd_ifcs = 0x02000000l in
    let dcmd_dext = 0x20000000l in
    let dtyp_data = 0x00300000l in
    let ( lor ) = Int32.logor in
    dcmd_eop lor dcmd_rs lor dcmd_ifcs lor dcmd_dext lor dtyp_data in
  let size = Int32.of_int size in
  set_adv_tx_read_cmd_type_len
    cs
    (Int32.logor const_part size);
  let paylen_shift = 14 in
  set_adv_tx_read_olinfo_status
    cs
    (Int32.shift_left size paylen_shift)
