type dma_memory = {
  virt : Cstruct.t;
  (** DMA memory wrapped in a Cstruct.t. *)
  physical : Cstruct.uint64
  (** Physical address of the beginning of the DMA memory buffer. *)
}
(** Type of allocated DMA-ready memory. *)

val huge_page_size : int
(** [huge_page_size] is the size of a single huge page. (2 MiB) *)

val huge_page_bits : int
(** [huge_page_bits] is the number of bits required for addressing inside
    a huge page ([21]). *)

val int64_of_addr : Cstruct.t -> Cstruct.uint64

type mempool = { (* not private so Ixy.tx_batch can free buffers directly *)
  entry_size : int;
  num_entries : int;
  mutable free : int;
  free_bufs : pkt_buf array;
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

val dummy : pkt_buf
(** [dummy] is a dummy [pkt_buf] that can be used to pre-fill arrays.
    Raises [Invalid_argument] exception when freed. *)
