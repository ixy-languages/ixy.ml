val pagesize : int
(** [pagesize] is the size of a system page in bytes. *)

type dma_memory = private {
  virt : Cstruct.t;
  (** DMA memory wrapped in a Cstruct.t. *)
  physical : Cstruct.uint64
  (** Physical address of the beginning of the DMA memory buffer. *)
}
(** Type of allocated DMA-ready memory. *)

val huge_page_size : int
(** [huge_page_size] is the size of a single huge page. (2 MiB) *)

val allocate_dma : ?require_contiguous:bool -> int -> dma_memory
(** [allocate_dma ~require_contiguous n] allocates [n] bytes of DMA memory
    in the hugetlbfs. If [require_contiguous] is [true] the DMA memory
    returned will have contiguous physical addresses; fails if [n] is larger
    than [huge_page_size]. *)

type mempool = { (* not private so Ixy.tx_batch can free buffers directly *)
  entry_size : int;
  num_entries : int;
  mutable free_bufs : pkt_buf list
}
(** Type of a memory pool. *)

and pkt_buf = { (* not private so Ixy.rx_batch can write size directly *)
  phys : Cstruct.uint64;
  (** Physical address of the [data] field's underlying [Cstruct.buffer]. *)
  mempool : mempool;
  (** Mempool this packet belongs to. *)
  mutable size : int;
  (** Actual size of the payload within the [data] field. *)
  data : Cstruct.t
  (** Packet payload; always 2048 bytes in size. *)
}
(** Type of a packet buffer. *)

val allocate_mempool : ?pre_fill:Cstruct.t -> num_entries:int -> mempool
(** [allocate_mempool ~pre_fill:data ~num_entries] allocates a mempool
    with [num_entries] packet buffers. If [pre_fill] is provided, the packet
    buffers will be initialized with [data] and their length will be set to
    [data]'s length. Otherwise the [pkt_buf]s are zeroed and their initial
    size will be set to 2048. *)

val pkt_buf_alloc_batch : mempool -> num_bufs:int -> pkt_buf list
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

val dummy : pkt_buf
(** [dummy] is a dummy [pkt_buf] that can be used to pre-fill arrays.
    Raises [Invalid_argument] exception when freed. *)
