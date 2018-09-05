open Core

type virt

val nullptr : virt

type dma_memory = private {
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

val mmap : int -> prot list -> map list -> Unix.File_descr.t -> int -> virt

val munmap : virt -> int -> unit

val mlock : virt -> int -> unit

val munlock : virt -> int -> unit

val virt_to_phys : virt -> int64

val c_virt_to_phys : virt -> int64 (* should return the same as virt_to_phys *)

val allocate_dma : ?require_contiguous:bool -> int -> dma_memory

val test_string : string -> unit

val read64 : virt -> int -> int64

val write64 : virt -> int -> int64 -> unit

val read32 : virt -> int -> int

val write32 : virt -> int -> int -> unit

val read16 : virt -> int -> int

val write16 : virt -> int -> int -> unit

val read8 : virt -> int -> int

val write8 : virt -> int -> int -> unit

val offset_ptr : virt -> int -> virt

val make_ocaml_string : virt -> int -> string

val get_string : unit -> virt

val c_dump_memory : string -> virt -> int -> unit

val dump_memory : string -> virt -> int -> unit

val malloc : int -> virt

type mempool

val allocate_mempool : ?entry_size:int -> num_entries:int -> mempool

type pkt_buf

val pkt_buf_resize : pkt_buf -> int -> unit

val pkt_buf_get_data : pkt_buf -> bytes

val pkt_buf_get_phys : pkt_buf -> int64

val pkt_buf_alloc_batch : mempool -> num_bufs:int -> pkt_buf array

val pkt_buf_alloc : mempool -> pkt_buf option

val pkt_buf_free : pkt_buf -> unit
