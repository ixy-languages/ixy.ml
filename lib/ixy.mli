val max_rx_queue_entries : int

val max_tx_queue_entries : int

val num_rx_queue_entries : int

val num_tx_queue_entries : int

(* TODO delete after testing *)

type rxq = private {
  descriptors : Memory.virt;
  mempool : Memory.mempool;
  num_entries : int;
  mutable rx_index : int; (* descriptor ring tail pointer  *)
  virtual_addresses : Memory.pkt_buf array;
}

type txq = private {
  descriptors : Memory.virt;
  num_entries : int;
  mutable clean_index : int; (* first unclean descriptor *)
  mutable tx_index : int; (* descriptor ring tail pointer *)
  virtual_addresses : Memory.pkt_buf option array; (* TODO might be unboxed *)
}

type t = private {
  hw : PCI.hw;
  pci_addr : string;
  num_rxq : int;
  mutable rxqs : rxq array; (* TODO mutability needed? *)
  num_txq : int;
  mutable txqs : txq array;
  get_reg : int IXGBE.register -> int;
  set_reg : int IXGBE.register -> int -> unit;
  set_flags : int IXGBE.register -> int -> unit;
  clear_flags : int IXGBE.register -> int -> unit;
  wait_set : int IXGBE.register -> int -> unit;
  wait_clear : int IXGBE.register -> int -> unit
}

val create : pci_addr:string -> rxq:int -> txq:int -> t

val rx_batch : t -> int -> Memory.pkt_buf list

val tx_batch : ?clean_large:bool -> t -> int -> Memory.pkt_buf list -> Memory.pkt_buf list

val reset : t -> unit (* may need to remove this *)

val blink_mode : t -> [ `LED0 | `LED1 | `LED2 | `LED3 ] -> bool -> unit

val check_link : t -> [ `SPEED_10G | `SPEED_1G | `SPEED_100 | `SPEED_UNKNOWN ] * bool

module Memory = Memory

module Uname = Uname

module Log = Log

module PCI = PCI
