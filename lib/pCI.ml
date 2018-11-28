open Core

type t = string

let of_string str =
  if Scanf.sscanf str "%4x:%2x:%2x.%1x" (sprintf "%04x:%02x:%02x.%1x") <> str then
    None
  else
    Some str

let to_string t = t

type hw = Cstruct.t

let remove_driver t =
  let path =
    sprintf "/sys/bus/pci/devices/%s/driver/unbind" t in
  try
    let oc = Out_channel.create path in
    Out_channel.output_string oc t;
    Out_channel.close oc
  with Sys_error _ -> Log.debug "no driver loaded"

let conf_path t =
  sprintf "/sys/bus/pci/devices/%s/config" t

let enable_dma t =
  let fd = Unix.(openfile ~mode:[O_RDWR] (conf_path t)) in
  (* we can't mmap the PCI configuration space. *)
  assert (Unix.lseek fd 4L ~mode:SEEK_SET = 4L);
  let dma = Bytes.create 2 in
  assert (Unix.read fd ~len:2 ~buf:dma = 2);
  let low = Char.to_int @@ Bytes.get dma 0 in
  Bytes.set dma 0 (Char.of_int_exn (low lor (1 lsl 2)));
  assert (Unix.lseek fd 4L ~mode:SEEK_SET = 4L);
  (* maybe the write needs to be 2 byte? *)
  assert (Unix.write fd ~len:2 ~buf:dma = 2);
  Unix.close fd

let map_resource t =
  remove_driver t;
  enable_dma t;
  let path = sprintf "/sys/bus/pci/devices/%s/resource0" t in
  let fd = Unix.(openfile ~mode:[O_RDWR] path) in
  let hw = Util.mmap fd in
  (* ixy doesn't do this but there shouldn't be a reason to keep fd around *)
  Unix.close fd;
  hw

type pci_config = {
  vendor : int;
  device_id : int;
  class_code : int;
  subclass : int;
  prog_if : int
}

[%%cstruct
  type pci_conf_space = {
    vendor_id : uint16_t;
    device_id : uint16_t;
    command : uint16_t;
    status : uint16_t;
    revision_id : uint8_t;
    prog_if : uint8_t;
    subclass : uint8_t;
    class_code : uint8_t
  } [@@little_endian] (* PCI configuration space is always little endian *)
]

let get_config t =
  if Ixy_dbg.testing then
    { vendor = 0; device_id = 0; class_code = 0; subclass = 0; prog_if = 0 }
  else begin
    let ic = In_channel.create (conf_path t) in
    let cstruct =
      let buf = Bytes.create sizeof_pci_conf_space in
      assert (In_channel.input ic ~buf ~pos:0 ~len:sizeof_pci_conf_space = sizeof_pci_conf_space);
      In_channel.close ic;
      Cstruct.of_bytes buf in
    { vendor = get_pci_conf_space_vendor_id cstruct;
      device_id = get_pci_conf_space_device_id cstruct;
      class_code = get_pci_conf_space_class_code cstruct;
      subclass = get_pci_conf_space_subclass cstruct;
      prog_if = get_pci_conf_space_prog_if cstruct
    }
  end

let vendor_intel = 0x8086
