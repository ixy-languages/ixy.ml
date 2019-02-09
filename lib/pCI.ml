[@@@ocaml.warning "-32"]

type t = string

let of_string str =
  PCI_addr.check str

let to_string t = t

type hw =
  (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

let remove_driver t =
  let path =
    Printf.sprintf "/sys/bus/pci/devices/%s/driver/unbind" t in
  try
    let oc = open_out path in
    output_string oc t;
    close_out oc
  with Sys_error _ -> Log.debug "no driver loaded"

let conf_path t =
  Printf.sprintf "/sys/bus/pci/devices/%s/config" t

let enable_dma t =
  let fd = Unix.(openfile (conf_path t) [O_RDWR] 0o644) in
  (* we can't mmap the PCI configuration space. *)
  assert Unix.(lseek fd 4 SEEK_SET = 4);
  let dma = Bytes.create 2 in
  assert (Unix.read fd dma 0 2 = 2);
  let low = int_of_char @@ Bytes.get dma 0 in
  Bytes.set dma 0 (char_of_int (low lor (1 lsl 2)));
  assert Unix.(lseek fd 4 SEEK_SET = 4);
  (* maybe the write needs to be 2 byte? *)
  assert (Unix.write fd dma 0 2 = 2);
  Unix.close fd

let map_resource t =
  remove_driver t;
  enable_dma t;
  let path = Printf.sprintf "/sys/bus/pci/devices/%s/resource0" t in
  let fd = Unix.(openfile path [O_RDWR] 0o644) in
  let hw =
    Bigarray.(Unix.map_file fd char c_layout true [|-1|])
    |> Bigarray.array1_of_genarray in
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
  let ic = open_in (conf_path t) in
  let cstruct =
    let buf = Bytes.create sizeof_pci_conf_space in
    assert (input ic buf 0 sizeof_pci_conf_space = sizeof_pci_conf_space);
    close_in ic;
    Cstruct.of_bytes buf in
  { vendor = get_pci_conf_space_vendor_id cstruct;
    device_id = get_pci_conf_space_device_id cstruct;
    class_code = get_pci_conf_space_class_code cstruct;
    subclass = get_pci_conf_space_subclass cstruct;
    prog_if = get_pci_conf_space_prog_if cstruct
  }

let vendor_intel = 0x8086
