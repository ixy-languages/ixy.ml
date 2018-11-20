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
  num_entries : int; (** Number of descriptors in the ring. *)
  mutable rx_index : int; (** Descriptor ring tail pointer. *)
  pkt_bufs : Memory.pkt_buf array; (** [pkt_bufs.(i)] contains the buffer corresponding to [descriptors.(i)] for [0] <= [i] < [num_entries]. *)
}
(** Type of a receive queue. *)

type txq = private {
  descriptors : TXD.t array; (** TX descriptor ring. *)
  num_entries : int; (** Number of descriptors in the ring. *)
  mutable clean_index : int; (** Pointer to first unclean descriptor. *)
  mutable tx_index : int; (** Descriptor ring tail pointer. *)
  pkt_bufs : Memory.pkt_buf array; (** [pkt_bufs.(i)] contains the buffer corresponding to [descriptors.(i)] for [0] <= [i] < [num_entries]. Initially filled with [Memory.dummy]. *)
}
(** Type of a transmit queue. *)

type t = private {
  hw : PCI.hw;
  pci_addr : string;
  num_rxq : int;
  mutable rxqs : rxq array; (* TODO mutability needed? *)
  num_txq : int;
  mutable txqs : txq array;
  get_reg : IXGBE.register -> int32;
  set_reg : IXGBE.register -> int32 -> unit;
  set_flags : IXGBE.register -> int32 -> unit;
  clear_flags : IXGBE.register -> int32 -> unit;
  wait_set : IXGBE.register -> int32 -> unit;
  wait_clear : IXGBE.register -> int32 -> unit
}
(** Type of an ixgbe NIC. *)

val create : pci_addr:PCI.t -> rxq:int -> txq:int -> t
(** [create ~pci_addr ~rxq ~txq] initializes the NIC located at [pci_addr]
    with [rxq] receive queues and [txq] transmit queues. *)

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

val reset : t -> unit (* may need to remove this *)
(** [reset t] resets the NIC [t]. Do not use [t] after resetting! *)

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
