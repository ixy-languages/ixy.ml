open Core

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

val mmap : int -> prot list -> map list -> Unix.File_descr.t -> int -> virt

val munmap : virt -> int -> unit

val mlock : virt -> int -> unit

val munlock : virt -> int -> unit

val virt_to_phys : virt -> int64

val c_virt_to_phys : virt -> int64 (* should return the same as virt_to_phys *)

val allocate_dma : ?require_contiguous:bool -> int -> dma_memory

val test_string : string -> unit

val read32 : virt -> int -> int

val write32 : virt -> int -> int -> unit

val read8 : virt -> int -> int

val write8 : virt -> int -> int -> unit
