open Ixy_memory

type hw =
  (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t
(** Type of register files (also called [hw] in the linux ixgbe driver). *)

type pci_config =
  { vendor : int
  ; device_id : int
  ; class_code : int
  ; subclass : int
  ; prog_if : int
  }
(** Type of the PCIe configuration space. *)

val vendor_intel : int
(** Intel's vendor ID ([0x8086] in little endian). *)

module type S = sig
  type t
  (** Type of PCIe devices. *)

  val map_resource : t -> hw
  (** [map_resource t] maps [t]'s register file. *)

  val get_config : t -> pci_config
  (** [get_config t] returns the PCIe configuration space for [t]. *)

  val to_string : t -> string

  val allocate_dma : t -> ?require_contiguous:bool -> int -> Ixy_memory.dma_memory option
  (** [allocate_dma ~require_contiguous n] allocates [n] bytes of DMA memory.
      If [require_contiguous] is [true] the DMA memory returned will have contiguous
      physical addresses. *)

  val virt_to_phys : Cstruct.t -> Cstruct.uint64
end


module type Memory = sig
  include S

  val allocate_mempool : t -> ?pre_fill:Cstruct.t -> num_entries:int -> mempool
  (** [allocate_mempool ~pre_fill:data ~num_entries] allocates a mempool
      with [num_entries] packet buffers. If [pre_fill] is provided, the packet
      buffers will be initialized with [data] and their length will be set to
      [data]'s length. Otherwise the [pkt_buf]s are zeroed and their initial
      size will be set to 2048. *)

  val num_free_bufs : mempool -> int
  (** [num_free_bufs mempool] returns the number of free buffers in [mempool]. *)

  val pkt_buf_alloc_batch : mempool -> num_bufs:int -> pkt_buf array
  (** [pkt_buf_alloc_batch mempool ~num_bufs] attempts to allocate [num_bufs]
      packet buffers in [mempool]. If there are fewer than [num_bufs] free
      buffers in [mempool], all of them will be allocated. Errors and quits the
      program, if [num_bufs] is greater than the [mempool]'s size; this is likely
      to have happened due to a logic error. *)

  val pkt_buf_alloc : mempool -> pkt_buf option
  (** [pkt_buf_alloc mempool] attempts to allocate a single packet buffer in
      [mempool]. Returns [None] if there are no free buffers in [mempool]. *)

  val pkt_buf_resize : pkt_buf -> size:int -> unit
  (** [pkt_buf_resize buf ~size] attempts to resize [buf] to [size].
      Fails if [size] is negative or larger than the [mempool]'s [entry_size]. *)

  val pkt_buf_free : pkt_buf -> unit
  (** [pkt_buf_free buf] deallocates [buf] and returns it to its [mempool].
      IMPORTANT: Currently double frees are neither detected nor handled!
      Double frees will violate the [mempool]'s invariants! *)
end

module Make (Pci : S) : Memory with type t := Pci.t
