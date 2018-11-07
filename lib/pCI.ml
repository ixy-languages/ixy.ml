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
    let fd = Unix.(openfile ~mode:[O_WRONLY] path) in
    let buf = Bytes.unsafe_of_string_promise_no_mutation t in
    if Unix.(write fd ~buf) <> String.length t then
      Log.warn "failed to unload driver for device %s" t;
    Unix.close fd
  with Unix.Unix_error _ -> Log.debug "no driver loaded"

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

let get_configuration_space ?(writable = false) t =
  let path =
    sprintf "/sys/bus/pci/devices/%s/config" t in
  let mode = Unix.[if writable then O_RDWR else O_RDONLY] in
  try
    let fd = Unix.(openfile ~mode path) in
    let cs = Unix_cstruct.of_fd fd in
    Unix.close fd;
    cs
  with Unix.Unix_error _ -> Log.error "couldn't open PCIe configuration space"

let enable_dma t =
  let config = get_configuration_space ~writable:true t in
  let dma = get_pci_conf_space_command config in
  set_pci_conf_space_command config (dma lor (1 lsl 2))

let map_resource t =
  let path = sprintf "/sys/bus/pci/devices/%s/resource0" t in
  let fd = Unix.(openfile ~mode:[O_RDWR] path) in
  let hw = Unix_cstruct.of_fd fd in
  remove_driver t;
  enable_dma t;
  Unix.close fd; (* ixy doesn't do this but there shouldn't be a reason to keep fd around *)
  hw

let get_config t =
  if Ixy_dbg.testing then
    { vendor = 0; device_id = 0; class_code = 0; subclass = 0; prog_if = 0 }
  else begin
    let cstruct = get_configuration_space t in
    { vendor = get_pci_conf_space_vendor_id cstruct;
      device_id = get_pci_conf_space_device_id cstruct;
      class_code = get_pci_conf_space_class_code cstruct;
      subclass = get_pci_conf_space_subclass cstruct;
      prog_if = get_pci_conf_space_prog_if cstruct
    }
  end

let vendor_intel = 0x8086
