open Core
open Log

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

let stat_dd = 0b1l

let dd t = Int32.((get_adv_tx_wb_status t) land stat_dd <> 0l)

let split num cs =
  let len = Cstruct.len cs in
  if num * sizeof > len then
    error "cstruct is too small (%d bytes) for %d descriptors" len num;
  Array.init
    num
    ~f:(fun i -> Cstruct.sub cs (i * sizeof) sizeof)

let dcmd_eop = 0x01000000l

let dcmd_rs = 0x08000000l

let dcmd_ifcs = 0x02000000l

let dcmd_dext = 0x20000000l

let dtyp_data = 0x00300000l

let paylen_shift = 14

let reset cs Memory.{ size; phys; _ } =
  set_adv_tx_read_buffer_addr cs phys;
  let size = Int32.of_int_exn size in
  set_adv_tx_read_cmd_type_len
    cs
    Int32.(dcmd_eop lor dcmd_rs lor dcmd_ifcs lor dcmd_dext lor dtyp_data lor size);
  set_adv_tx_read_olinfo_status cs Int32.(size lsl paylen_shift)
