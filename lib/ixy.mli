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
  rxds : RXD.t array;
  (** RX descriptor ring. *)
  mempool : Memory.mempool;
  (** [mempool] from which to allocate receive buffers. *)
  mutable rx_index : int;
  (** Descriptor ring tail pointer. *)
  rx_bufs : Memory.pkt_buf array
  (** [pkt_bufs.(i)] contains the buffer corresponding to
      [descriptors.(i)] for [0] <= [i] < [num_entries]. *)
}
(** Type of a receive queue. *)

type txq = private {
  txds : TXD.t array;
  (** TX descriptor ring. *)
  mutable clean_index : int;
  (** Pointer to first unclean descriptor. *)
  mutable tx_index : int;
  (** Descriptor ring tail pointer. *)
  tx_bufs : Memory.pkt_buf array
  (** [pkt_bufs.(i)] contains the buffer corresponding to
      [descriptors.(i)] for [0] <= [i] < [num_entries].
      Initially filled with [Memory.dummy]. *)
}
(** Type of a transmit queue. *)

type register_access = private {
  get_reg : IXGBE.register -> int32;
  set_reg : IXGBE.register -> int32 -> unit;
  set_flags : IXGBE.register -> int32 -> unit;
  clear_flags : IXGBE.register -> int32 -> unit;
  wait_set : IXGBE.register -> int32 -> unit;
  wait_clear : IXGBE.register -> int32 -> unit
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

val rx_batch : ?batch_size:int -> t -> int -> Memory.pkt_buf array
(** [rx_batch dev queue] receives packets from [dev]'s queue [queue].
    Returns between [0] and [num_rx_queue_entries] packets.
    If [batch_size] is specified then between [0] and [batch_size] packets
    will be returned. *)

val tx_batch : t -> int -> Memory.pkt_buf array -> Memory.pkt_buf array
(** [tx_batch dev queue bufs] attempts to transmit [bufs] on
    [dev]'s queue [queue]. Returns the unsent packets. *)

val tx_batch_busy_wait : t -> int -> Memory.pkt_buf array -> unit
(** [tx_batch_busy_wait dev queue bufs] busy waits until all [bufs]
    have been transmitted on [dev]'s queue [queue] by repeatedly calling
    [tx_batch]. *)

val check_link :
  t -> [ `SPEED_10G | `SPEED_1G | `SPEED_100 | `SPEED_UNKNOWN ] * bool
(** [check_link dev] returns [dev]'s autoconfigured speed and wether
    or not the link is up. *)

module Memory = Memory
(** Packet buffers and memory pools. *)

module Uname = Uname
(** System information. *)

module Log = Log
(** Logging. *)

module PCI = PCI
(** PCIe interface via sysfs. *)

module IXGBE = IXGBE
(** Register access. *)
