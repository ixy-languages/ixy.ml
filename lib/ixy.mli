val max_rx_queue_entries : int

val max_tx_queue_entries : int

val num_rx_queue_entries : int

val num_tx_queue_entries : int

(* TODO delete after testing *)

type rxq = private {
  descriptors : RXD.t array;
  mempool : Memory.mempool;
  num_entries : int;
  mutable rx_index : int; (* descriptor ring tail pointer  *)
  pkt_bufs : Memory.pkt_buf array;
}

type txq = private {
  descriptors : TXD.t array;
  num_entries : int;
  mutable clean_index : int; (* first unclean descriptor *)
  mutable tx_index : int; (* descriptor ring tail pointer *)
  pkt_bufs : Memory.pkt_buf option array; (* TODO might be unboxed *)
}

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

val check_link : t -> [ `SPEED_10G | `SPEED_1G | `SPEED_100 | `SPEED_UNKNOWN ] * bool
(** [check_link dev] returns [dev]'s autoconfigured speed and wether
    or not the link is up. *)

module Memory = Memory

module Uname = Uname

module Log = Log

module PCI = PCI
