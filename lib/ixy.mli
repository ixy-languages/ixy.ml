val max_queues : int
(** Maximum number of queues. *)

val max_rx_queue_entries : int
(** Maximum number of receive queue entries. *)

val max_tx_queue_entries : int
(** Maximum number of transmit queue entries. *)

val num_rx_queue_entries : int
(** Number of receive queue entries. *)

val num_tx_queue_entries : int
(** Number of transmit queue entries. *)

module Memory : sig
  val pagesize : int
  (** [pagesize] is the size of a system page in bytes. *)

  type idx

  type mempool
  (** Type of a memory pool. *)

  val allocate_mempool : ?pre_fill:Cstruct.t -> num_entries:int -> mempool
  (** [allocate_mempool ~pre_fill:data ~num_entries] allocates a mempool
      with [num_entries] packet buffers. If [pre_fill] is provided, the packet
      buffers will be initialized with [data] and their length will be set to
      [data]'s length. Otherwise the [pkt_buf]s are zeroed and their initial
      size will be set to 2048. *)

  val num_free_bufs : mempool -> int
  (** [num_free_bufs mempool] returns the number of free buffers in [mempool]. *)

  type pkt_buf = private {
    phys : Cstruct.uint64;
    (** Physical address of the [data] field's underlying [Cstruct.buffer]. *)
    mempool : mempool;
    (** Mempool this packet belongs to. *)
    mutable size : int;
    (** Actual size of the payload within the [data] field. *)
    data : Cstruct.t;
    (** Packet payload; always 2048 bytes in size. *)
    mempool_idx : idx
  }
  (** Type of a packet buffer. *)

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
end
(** Packet buffers and memory pools. *)

module RXD : sig
  type t
  (** Type of receive descriptors. *)

  val sizeof : int
  (** [sizeof] is the size of a receive descriptor in bytes. Equal to 16. *)

  val split : int -> Cstruct.t -> t array
  (** [split n cstruct] splits [cstruct] into [n] receive descriptors. *)

  val dd : t -> bool
  (** [dd rxd] returns [true] if [rxd]'s DD and EOP bits are set.
      Fails if DD is set, but EOP is not set (jumbo frame).
      Returns [false] otherwise. *)

  val size : t -> int
  (** [size rxd] returns [rxd]'s size in bytes. *)

  val reset : t -> Memory.pkt_buf -> unit
  (** [reset rxd buf] resets [rxd] by resetting its flags and pointing
      it to the buffer [buf]. *)
end
(** Receive descriptor handling. *)

module TXD : sig
  type t
  (** Type of transmit descriptors. *)

  val sizeof : int
  (** [sizeof] is the size of a transmit descriptor in bytes. Equal to 16. *)

  val split : int -> Cstruct.t -> t array
  (** [split n cstruct] splits [cstruct] into [n] transmit descriptors. *)

  val dd : t -> bool
  (** [dd txd] returns true if [txd]'s stat_dd bit is set,
      i.e. the packet that has been placed in the corresponding
      buffer was sent out by the NIC. *)

  val reset : t -> Memory.pkt_buf -> unit
  (** [reset txd buf] resets [txd] by resetting its flags and pointing
      it to the buffer [buf]. *)
end
(** Transmit descriptor handling. *)

type rxq = private {
  rdt : IXGBE.reg;
  rxds : RXD.t array;
  (** RX descriptor ring. *)
  mempool : Memory.mempool;
  (** [mempool] from which to allocate receive buffers. *)
  mutable rx_index : int;
  (** Descriptor ring tail pointer. *)
  rx_bufs : Memory.idx array
  (** [pkt_bufs.(i)] contains the buffer corresponding to
      [descriptors.(i)] for [0] <= [i] < [num_entries]. *)
}
(** Type of a receive queue. *)

type txq = private {
  tdt : IXGBE.reg;
  txds : TXD.t array;
  (** TX descriptor ring. *)
  mutable clean_index : int;
  (** Pointer to first unclean descriptor. *)
  mutable tx_index : int;
  (** Descriptor ring tail pointer. *)
  tx_bufs : Memory.idx array
  (** [pkt_bufs.(i)] contains the buffer corresponding to
      [descriptors.(i)] for [0] <= [i] < [num_entries].
      Initially filled with [Memory.dummy]. *)
}
(** Type of a transmit queue. *)

type register_access = private {
  get_reg : IXGBE.register -> int;
  set_reg : IXGBE.register -> int -> unit;
  set_flags : IXGBE.register -> int -> unit;
  clear_flags : IXGBE.register -> int -> unit;
  wait_set : IXGBE.register -> int -> unit;
  wait_clear : IXGBE.register -> int -> unit
}
(** Type of register access function set. *)

type stats = private {
  mutable rx_pkts : int;
  mutable tx_pkts : int;
  mutable rx_bytes : int;
  mutable tx_bytes : int
}
(** Type of statistics. *)

type t = private {
  hw : PCI.hw;
  pci_addr : string;
  num_rxq : int;
  rxqs : rxq array;
  num_txq : int;
  txqs : txq array;
  ra : register_access;
  stats : stats
}
(** Type of an ixgbe NIC. *)

val create : pci_addr:PCI.t -> rxq:int -> txq:int -> t
(** [create ~pci_addr ~rxq ~txq] initializes the NIC located at [pci_addr]
    with [rxq] receive queues and [txq] transmit queues. *)

val shutdown : t -> unit
(** [shutdown dev] disables [dev]'s rx and tx queues and resets the device.
    The device must not be used afterwards. *)

val get_mac : t -> Cstruct.t
(** [get_mac dev] returns [dev]'s MAC address. *)

val set_promisc : t -> bool -> unit
(** [set_promisc dev true] enables promiscuous mode on [dev].
    [set_promisc dev false] disables promiscuous mode on [dev].
    In promisuous mode all packets received by the NIC are
    forwarded to the driver, regardless of MAC address. *)

val reset_stats : t -> unit
(** [reset_stats dev] resets packet and byte counters on [dev].
    Statistics registers will also be reset. *)

val get_stats : t -> stats
(** [get_stats dev] returns the number of packets/bytes received/sent
    on [dev] since initialization or the last call to [reset_stats]. *)

val rx_batch : ?batch_size:int -> t -> int -> Memory.pkt_buf list
(** [rx_batch dev queue] receives packets from [dev]'s queue [queue].
    Returns between [0] and [num_rx_queue_entries] packets.
    If [batch_size] is specified then between [0] and [batch_size] packets
    will be returned. *)

val tx_batch : t -> int -> Memory.mempool -> Memory.pkt_buf list -> Memory.pkt_buf list
(** [tx_batch dev queue bufs] attempts to transmit [bufs] on
    [dev]'s queue [queue]. Returns the unsent packets. *)

val tx_batch_busy_wait : t -> int -> Memory.mempool -> Memory.pkt_buf list -> unit
(** [tx_batch_busy_wait dev queue bufs] busy waits until all [bufs]
    have been transmitted on [dev]'s queue [queue] by repeatedly calling
    [tx_batch]. *)

val check_link :
  t -> [ `SPEED_10G | `SPEED_1G | `SPEED_100 | `SPEED_UNKNOWN ] * bool
(** [check_link dev] returns [dev]'s autoconfigured speed and wether
    or not the link is up. *)

module Uname = Uname
(** System information. *)

module Log = Log
(** Logging. *)

module PCI = PCI
(** PCIe interface via sysfs. *)

module IXGBE = IXGBE
(** Register access. *)
