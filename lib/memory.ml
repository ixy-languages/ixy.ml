open Log

type dma_memory = {
  virt : Cstruct.t;
  phys : Cstruct.uint64
}

external pagesize : unit -> int = "ixy_pagesize"

let pagesize = pagesize ()

external ixy_int64_of_addr :
  Cstruct.buffer -> int -> Cstruct.uint64 = "ixy_int64_of_addr"

let int64_of_addr Cstruct.{ buffer; off; _ } =
  ixy_int64_of_addr buffer off

external ixy_mlock : Cstruct.buffer -> int -> int -> unit = "ixy_mlock"

let mlock Cstruct.{ buffer; off; len } =
  ixy_mlock buffer off len

let virt_to_phys virt =
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

let huge_page_id = ref 0

let huge_page_bits = 21
let huge_page_size = 1 lsl huge_page_bits

let allocate_dma ?(require_contiguous = true) size =
  let size =
    if size mod huge_page_size <> 0 then
      ((size lsr huge_page_bits) + 1) lsl huge_page_bits
    else
      size in
  if require_contiguous && size > huge_page_size then
    error "cannot map contiguous memory";
  let pid = Unix.getpid () in
  let path =
    Printf.sprintf "/mnt/huge/ixy.ml-%d-%d" pid !huge_page_id in
  incr huge_page_id;
  let fd = Unix.(openfile path [O_CREAT; O_RDWR] 0o777) in
  Unix.ftruncate fd size;
  let virt = Util.mmap fd in
  assert (Cstruct.len virt = size); (* TODO maybe remove this later? *)
  mlock virt;
  Unix.close fd;
  Unix.unlink path;
  let phys = virt_to_phys virt in
  debug
    "allocated %#x bytes of dma memory at virt %#018Lx, phys %#018Lx"
    size
    (int64_of_addr virt)
    phys;
  { virt; phys }

type mempool = {
  entry_size : int;
  num_entries : int;
  mutable free : int;
  free_bufs : pkt_buf array;
}

and pkt_buf = {
  phys : Cstruct.uint64;
  mempool : mempool;
  mutable size : int;
  data : Cstruct.t
}

let dummy =
  let dummy_pool =
    { entry_size = 0;
      num_entries = 0;
      free = 0;
      free_bufs = [||] (* ensure out of bounds write when freed *)
    } in
  { phys = 0L;
    mempool = dummy_pool;
    size = 0;
    data = Cstruct.empty
  }

let allocate_mempool ?pre_fill ~num_entries =
  let entry_size = 2048 in (* entry_size is fixed for now *)
  if huge_page_size mod entry_size <> 0 then
    error "entry size must be a divisor of huge page size (%d)" huge_page_size;
  let { virt; _ } =
    allocate_dma ~require_contiguous:false (num_entries * entry_size) in
  Cstruct.memset virt 0; (* might not be necessary *)
  let mempool =
    { entry_size;
      num_entries;
      free = num_entries;
      free_bufs = Array.make num_entries dummy
    } in
  let init_buf index =
    let data =
      Cstruct.sub virt (index * entry_size) entry_size in
    let size =
      match pre_fill with
      | Some init ->
        let len = Cstruct.len init in
        Cstruct.blit init 0 data 0 len;
        len
      | None -> entry_size in
    { phys = virt_to_phys data;
      mempool;
      size;
      data
    } in
  Array.iteri
    (fun i _ -> mempool.free_bufs.(i) <- init_buf i)
    mempool.free_bufs;
  mempool

let num_free_bufs mempool = mempool.free

let pkt_buf_alloc_batch mempool ~num_bufs =
  if num_bufs > mempool.num_entries then
    warn
      "can never allocate %d bufs in a mempool with %d bufs"
      num_bufs
      mempool.num_entries;
  let n = min num_bufs mempool.free in
  let alloc_start = mempool.free - n in
  let bufs = Array.sub mempool.free_bufs alloc_start n in
  mempool.free <- alloc_start;
  bufs

let pkt_buf_alloc mempool =
  (* doing "pkt_buf_alloc_batch mempool ~num_bufs:1" has a bit more overhead *)
  if mempool.free > 0 then
    let index = mempool.free - 1 in
    mempool.free <- index;
    Some mempool.free_bufs.(index)
  else
    None

let pkt_buf_free ({ mempool; _ } as buf) =
  mempool.free_bufs.(mempool.free) <- buf;
  mempool.free <- mempool.free + 1

let pkt_buf_resize ({ mempool; _ } as buf) ~size =
  (* MTU is fixed at 1518 by default. *)
  let upper = min mempool.entry_size IXGBE.default_mtu in
  if size > 0 && size <= upper then
    buf.size <- size
  else
    error "0 < size <= %d is not fulfilled; size = %d" upper size
