val max_queues : int
(** maximum number of queues *)

val max_rx_queue_entries : int
(** Maximum number of receive queue entries. *)

val max_tx_queue_entries : int
(** Maximum number of transmit queue entries. *)

val num_rx_queue_entries : int
(** Number of receive queue entries. *)

val num_tx_queue_entries : int
(** Number of transmit queue entries. *)

(* TODO delete after testing *)

type rxq = private {
  descriptors : RXD.t array; (** RX descriptor ring. *)
  mempool : Memory.mempool; (** [mempool] from which to allocate receive buffers. *)
  mutable rx_index : int; (** Descriptor ring tail pointer. *)
  pkt_bufs : Memory.pkt_buf array; (** [pkt_bufs.(i)] contains the buffer corresponding to [descriptors.(i)] for [0] <= [i] < [num_entries]. *)
}
(** Type of a receive queue. *)

type txq = private {
  descriptors : TXD.t array; (** TX descriptor ring. *)
  mutable clean_index : int; (** Pointer to first unclean descriptor. *)
  mutable tx_index : int; (** Descriptor ring tail pointer. *)
  pkt_bufs : Memory.pkt_buf array; (** [pkt_bufs.(i)] contains the buffer corresponding to [descriptors.(i)] for [0] <= [i] < [num_entries]. Initially filled with [Memory.dummy]. *)
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

type t = private {
  pci_addr : string;
  num_rxq : int;
  rxqs : rxq array;
  num_txq : int;
  txqs : txq array;
  ra : register_access;
  mutable rx_pkts : int;
  mutable tx_pkts : int;
  mutable rx_bytes : int;
  mutable tx_bytes : int
}
(** Type of an ixgbe NIC. *)

val create : pci_addr:PCI.t -> rxq:int -> txq:int -> t
(** [create ~pci_addr ~rxq ~txq] initializes the NIC located at [pci_addr]
    with [rxq] receive queues and [txq] transmit queues. *)

val shutdown : t -> unit
(** [shutdown dev] disables all rx and tx queues on [dev] and resets the device.
    The device must not be used afterwards. *)

val get_mac : t -> Cstruct.t
(** [get_mac dev] returns [dev]'s MAC address. *)

val set_promisc : t -> bool -> unit
(** [set_promisc dev true] enables promiscuous mode on [dev].
    [set_promisc dev false] disables promiscuous mode on [dev].
    In promisuous mode all packets received by the NIC are
    forwarded to the driver, regardless of MAC address. *)

type stats = private {
  rx_pkts : int;
  tx_pkts : int;
  rx_bytes : int;
  tx_bytes : int
}
(** Type of statistics. *)

val reset_stats : t -> unit
(** [reset_stats dev] resets packet and byte counters on [dev].
    Statistics registers will also be reset. *)

val get_stats : t -> stats
(** [get_stats dev] returns the number of packets/bytes received/sent
    on [dev] since initialization or the last call to [reset_stats]. *)

val rx_batch : t -> int -> Memory.pkt_buf array
(** [rx_batch dev queue] attempts to receive packets from [dev]'s queue [queue].
    Returns between [0] and [num_rx_queue_entries] packets. *)

val tx_batch : ?clean_large:bool -> t -> int -> Memory.pkt_buf array -> Memory.pkt_buf array
(** [tx_batch ~clean_large dev queue bufs] attempts to transmit [bufs] on
    [dev]'s queue [queue]. Returns the unsent packets. *)

val tx_batch_busy_wait : ?clean_large:bool -> t -> int -> Memory.pkt_buf array -> unit
(** [tx_batch_busy_wait ~clean_large dev queue bufs] busy waits until all [bufs]
    have been transmitted on [dev]'s queue [queue] by repeatedly calling
    [tx_batch]. *)

val check_link : t -> [ `SPEED_10G | `SPEED_1G | `SPEED_100 | `SPEED_UNKNOWN ] * bool
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
