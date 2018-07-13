open Core
open Log

type virt

type dma_memory = {
  virt : virt;
  phy : int64
}

type prot =
  | PROT_NONE
  | PROT_READ
  | PROT_WRITE
  | PROT_EXEC

type map =
  | MAP_SHARED
  | MAP_PRIVATE
  | MAP_FILE
  | MAP_FIXED
  | MAP_ANONYMOUS
  | MAP_32BIT (* Linux only *)
  | MAP_GROWSDOWN (* Linux only *)
  | MAP_HUGETLB (* Linux only *)
  | MAP_LOCKED (* Linux only *)
  | MAP_NONBLOCK (* Linux only *)
  | MAP_NORESERVE (* Linux only *)
  | MAP_POPULATE (* Linux only *)
  | MAP_STACK (* Linux only *)
  | MAP_NOCACHE (* macOS only *)
  | MAP_HASSEMAPHORE (* macOS only *)

external c_virt_to_phys : 'a -> int64 = "caml_virt_to_phys"
external int64_of_addr : 'a -> int64 = "caml_int64_of_addr"
external mlock : virt -> int -> unit = "caml_mlock"
external munlock : virt -> int -> unit = "caml_munlock"
external test_string : string -> unit = "caml_test_string"
external mmap : int -> prot list -> map list -> Unix.File_descr.t -> int -> virt = "caml_mmap"
external munmap : virt -> int -> unit = "caml_munmap"

(* raw memory access *)
external read32 : virt -> int -> int = "caml_read32"
external write32 : virt -> int -> int -> unit = "caml_write32"
external read8 : virt -> int -> int = "caml_read8"
external write8 : virt -> int -> int -> unit = "caml_write8"

let virt_to_phys virt =
  if Obj.is_int (Obj.repr virt) then
    raise (Invalid_argument "virt must be a pointer");
  let pagesize =
    match Unix.(sysconf PAGESIZE) with
    | None -> error "cannot get pagesize"
    | Some n -> n in
  let fd = Unix.(openfile ~mode:[O_RDONLY] "/proc/self/pagemap") in
  let addr = int64_of_addr virt in
  let offset = Int64.(addr / pagesize * 8L) in
  if Unix.(lseek fd offset ~mode:SEEK_SET <> offset) then
    error "lseek unsuccessful";
  let buf = Bytes.create 8 in
  if Unix.(read fd ~buf <> 8) then
    error "read unsuccessful";
  Unix.close fd;
  let phy =
    let f i =
      let i64 =
        Bytes.get buf i
        |> Char.to_int
        |> Int64.of_int in
      Int64.shift_left i64 (i * 8) in
    Int64.(f 0 + f 1 + f 2 + f 3 + f 4 + f 5 + f 6 + f 7) in
  Int64.((phy land 0x7f_ff_ff_ff_ff_ff_ffL) * pagesize + (addr % pagesize))

let huge_page_id = ref 0

let huge_page_bits = 21
let huge_page_size = 1 lsl huge_page_bits

let allocate_dma ?(require_contiguous = true) size =
  let size =
    if size % huge_page_size <> 0 then
      ((size lsr huge_page_bits) + 1) lsl huge_page_bits
    else
      size in
  if require_contiguous && size > huge_page_size then
    error "cannot map contiguous memory";
  let pid = Core_kernel.Pid.to_int @@ Unix.getpid () in
  let path = Printf.sprintf "/mnt/huge/ixy.ml-%d-%d" pid !huge_page_id in
  incr huge_page_id;
  let fd = Unix.(openfile ~mode:[O_CREAT; O_RDWR] ~perm:0o777 path) in
  Unix.ftruncate fd ~len:(Int64.of_int size);
  let virt =
    mmap size [PROT_READ; PROT_WRITE] [MAP_SHARED; MAP_HUGETLB] fd 0 in
  mlock virt size;
  Unix.close fd;
  Unix.unlink path;
  { virt; phy = virt_to_phys virt }
