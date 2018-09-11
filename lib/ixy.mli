val max_rx_queue_entries : int

val max_tx_queue_entries : int

val num_rx_queue_entries : int

val num_tx_queue_entries : int

type t

val create : pci_addr:string -> rxq:int -> txq:int -> t

val rx_batch : t -> int -> Memory.pkt_buf list

val tx_batch : ?clean_large:bool -> t -> int -> Memory.pkt_buf list -> Memory.pkt_buf list

val reset : t -> unit (* may need to remove this *)

val blink_mode : t -> [ `LED0 | `LED1 | `LED2 | `LED3 ] -> bool -> unit

val check_link : t -> [ `SPEED_10G | `SPEED_1G | `SPEED_100 | `SPEED_UNKNOWN ] * bool

module Memory = Memory

module Uname = Uname

module Log = Log
