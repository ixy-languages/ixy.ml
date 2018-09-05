open Core
open Log

type virt

type dma_memory = {
  virt : virt;
  phys : int64
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

external c_virt_to_phys : 'a -> int64 = "caml_virt_to_phys" (* for testing purposes *)
external int64_of_addr : 'a -> int64 = "caml_int64_of_addr"
external offset_ptr : virt -> int -> virt = "caml_offset_ptr"
external mlock : virt -> int -> unit = "caml_mlock"
external munlock : virt -> int -> unit = "caml_munlock"
external test_string : string -> unit = "caml_test_string"
external mmap : int -> prot list -> map list -> Unix.File_descr.t -> int -> virt = "caml_mmap"
external munmap : virt -> int -> unit = "caml_munmap"

(* raw memory access *)
external read64 : virt -> int -> int64 = "caml_read64"
external write64 : virt -> int -> int64 -> unit = "caml_write64"
external read32 : virt -> int -> int = "caml_read32"
external write32 : virt -> int -> int -> unit = "caml_write32"
external read16 : virt -> int -> int = "caml_read16"
external write16 : virt -> int -> int -> unit = "caml_write16"
external read8 : virt -> int -> int = "caml_read8"
external write8 : virt -> int -> int -> unit = "caml_write8"
external getnullptr : unit -> virt = "caml_getnullptr"

external make_ocaml_string : virt -> int -> string = "caml_make_ocaml_string"
external get_string : unit -> virt = "caml_get_string"
external c_dump_memory : string -> virt -> int -> unit = "caml_dump_memory"
external malloc : int -> virt = "caml_malloc"

let dump_memory file virt len =
  debug "dumping %#x bytes at virt %#018Lx" len (int64_of_addr virt);
  let oc = Out_channel.create (file ^ ".bin") in
  for i = 0 to len - 1 do
    Out_channel.output_byte oc (read8 virt i)
  done;
  Out_channel.close oc;
  c_dump_memory (file ^ "-c.bin") virt len

let nullptr = getnullptr ()

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
  let phys =
    let f i =
      let i64 =
        Bytes.get buf i
        |> Char.to_int
        |> Int64.of_int in
      Int64.shift_left i64 (i * 8) in
    Int64.(f 0 + f 1 + f 2 + f 3 + f 4 + f 5 + f 6 + f 7) in
  Int64.((phys land 0x7f_ff_ff_ff_ff_ff_ffL) * pagesize + (addr % pagesize))

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
  let phys = virt_to_phys virt in
  debug
    "allocated %#x bytes of dma memory at base address %#018Lx, physical address %#018Lx"
    size
    (int64_of_addr virt)
    phys;
  { virt; phys }

type mempool = {
  base_addr : virt;
  buf_size : int;
  num_entries : int;
  mutable num_free_bufs : int; (* keep a separate counter of free bufs so we don't have to recompute the list's length every time *)
  mutable free_bufs : pkt_buf list
}

and pkt_buf = {
  phys : int64;
  mempool : mempool;
  data : bytes (* this points to the beginning of the packet data in the huge page *)
}

external pkt_buf_resize : pkt_buf -> int -> unit = "caml_make_ocaml_string"

let max_pkt_size = 1983 (* TODO check this number *)

let allocate_mempool ?(entry_size = 2048) ~num_entries =
  if huge_page_size mod entry_size <> 0 then
    error "huge_page_size must be a multiple of entry_size";
  let mem =
    allocate_dma ~require_contiguous:false (num_entries * entry_size) in
  let mempool =
    { base_addr = mem.virt;
      buf_size = entry_size;
      num_entries;
      num_free_bufs = num_entries;
      free_bufs = [] (* we can't use mutual recursion here for some reason *)
    } in
  let free_bufs =
    List.init
      num_entries
      ~f:(fun i ->
          let data_address =
            offset_ptr mem.virt ((i * entry_size) + 64) in
          { phys = virt_to_phys data_address;
            mempool;
            data = (Obj.magic make_ocaml_string data_address (entry_size - 64) : bytes) (* TODO fix this crappy cast *)
          }) in
  (* kind of ugly to immediately redefine free_bufs here
   * OTOH it's mutable anyway *)
  mempool.free_bufs <- free_bufs;
  mempool

let pkt_buf_get_data { data; _ } = data

let pkt_buf_get_phys { phys; _ } = phys

let pkt_buf_alloc_batch mempool ~num_bufs =
  let num_bufs =
    if num_bufs > mempool.num_free_bufs then begin
      warn "mempool only has %d free bufs, requested %d" mempool.num_free_bufs num_bufs;
      mempool.num_free_bufs
    end else
      num_bufs in
  mempool.num_free_bufs <- mempool.num_free_bufs - num_bufs;
  Array.init
    num_bufs
    ~f:(fun _ ->
        match mempool.free_bufs with
        | hd :: tl ->
          mempool.free_bufs <- tl;
          hd
        | [] -> assert false)

let pkt_buf_alloc mempool =
  (* doing "pkt_buf_alloc_batch mempool ~num_bufs:1" has a bit more overhead *)
  match mempool.free_bufs with
  | hd :: tl ->
    mempool.free_bufs <- tl;
    mempool.num_free_bufs <- mempool.num_free_bufs - 1;
    Some hd
  | [] -> None

let pkt_buf_free buf =
  let mempool = buf.mempool in
  pkt_buf_resize buf max_pkt_size;
  mempool.free_bufs <- buf :: mempool.free_bufs;
  mempool.num_free_bufs <- mempool.num_free_bufs + 1
