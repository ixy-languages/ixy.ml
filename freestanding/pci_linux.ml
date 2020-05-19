open Ixy_core.Ixy_pci
open Ixy_core.Log
open Ixy_core.Ixy_memory

let have_iommu = ref false

type t =
  { addr : string
  ; vfio_fd : Unix.file_descr option
  }

external pci_attach : string -> Unix.file_descr = "ixy_pci_attach"

external vfio_enable_dma : Unix.file_descr -> unit = "ixy_enable_dma"

let of_string str =
  match Pci_addr.check str with
  | Some addr ->
    let vfio = Sys.file_exists (Printf.sprintf "/sys/bus/pci/devices/%s/iommu_group" addr) in
    if vfio then have_iommu := true;
    Some { addr; vfio_fd = if vfio then Some (pci_attach addr) else None }
  | None -> None

let to_string t = t.addr

let remove_driver t =
  let path =
    Printf.sprintf "/sys/bus/pci/devices/%s/driver/unbind" t.addr in
  try
    let oc = open_out path in
    output_string oc t.addr;
    close_out oc
  with Sys_error _ -> debug "no driver loaded"

let conf_path t =
  Printf.sprintf "/sys/bus/pci/devices/%s/config" t.addr

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

external vfio_map_region : Unix.file_descr -> Cstruct.buffer = "ixy_map_region"

let map_resource t =
  match t.vfio_fd with
  | Some fd ->
    info "using IOMMU via VFIO";
    vfio_enable_dma fd;
    vfio_map_region fd
  | None ->
    warn "not using IOMMU";
    remove_driver t;
    enable_dma t;
    let path = Printf.sprintf "/sys/bus/pci/devices/%s/resource0" t.addr in
    let fd = Unix.(openfile path [O_RDWR] 0o644) in
    let hw =
      Bigarray.(Unix.map_file fd char c_layout true [|-1|])
      |> Bigarray.array1_of_genarray in
    Unix.close fd;
    hw

[@@@ocaml.warning "-32"]
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
[@@@ocaml.warning "+32"]

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

external pagesize : unit -> int = "ixy_pagesize" [@@noalloc]

let pagesize = pagesize ()

external ixy_mlock :
  Cstruct.buffer -> int -> int -> unit = "ixy_mlock" [@@noalloc]

let mlock Cstruct.{ buffer; off; len } =
  ixy_mlock buffer off len

let virt_to_phys virt =
  if !have_iommu then
    int64_of_addr virt
  else begin
    if Obj.is_int (Obj.repr virt) then
      raise (Invalid_argument "virt must be a pointer");
    let fd = Unix.(openfile "/proc/self/pagemap" [O_RDONLY] 0o644) in
    let addr = int64_of_addr virt in
    let offset = (Int64.to_int addr) / pagesize * 8 in
    if Unix.(lseek fd offset SEEK_SET <> offset) then
      error "lseek unsuccessful";
    let buf = Bytes.create 8 in
    if Unix.(read fd buf 0 8 <> 8) then
      error "read unsuccessful";
    Unix.close fd;
    let phys =
      Cstruct.(LE.get_uint64 (of_bytes buf) 0) in
    let pagesize = Int64.of_int pagesize in
    let offset =
      let x = Int64.rem addr pagesize in
      if x < 0L then Int64.add x pagesize else x in
    Int64.(add (mul (logand phys 0x7F_FFFF_FFFF_FFFFL) pagesize) offset)
  end

let huge_page_id = ref 0

(* 'Unix_cstruct.of_fd' doesn't map the file as shared. *)
let mmap fd =
  let genarray =
    Bigarray.(Unix.map_file fd char c_layout true [|-1|]) in
  Cstruct.of_bigarray (Bigarray.array1_of_genarray genarray)

external vfio_allocate_dma : int -> Cstruct.buffer = "ixy_allocate_dma"

let allocate_dma { vfio_fd; _ } ?(require_contiguous = true) size =
  let size =
    if size mod huge_page_size <> 0 then
      ((size lsr huge_page_bits) + 1) lsl huge_page_bits
    else
      size in
  if vfio_fd <> None then begin
    let buf = vfio_allocate_dma size in
    let virt = Cstruct.of_bigarray buf in
    Some { virt; physical = int64_of_addr virt }
  end else begin
    if require_contiguous && size > huge_page_size then
      error "cannot map contiguous memory";
    let pid = Unix.getpid () in
    let path =
      Printf.sprintf "/mnt/huge/ixy.ml-%d-%d" pid !huge_page_id in
    incr huge_page_id;
    let fd = Unix.(openfile path [O_CREAT; O_RDWR] 0o777) in
    Unix.ftruncate fd size;
    let virt = mmap fd in
    mlock virt;
    Unix.close fd;
    Unix.unlink path;
    let physical = virt_to_phys virt in
    debug
      "allocated %#x bytes of dma memory at virt %#018Lx, phys %#018Lx"
      size
      (int64_of_addr virt)
      physical;
    Some { virt; physical }
  end
