type t

val create : pci_addr:string -> rxq:int -> txq:int -> t

val reset : t -> unit (* may need to remove this *)

val blink_mode : t -> [ `LED0 | `LED1 | `LED2 | `LED3 ] -> bool -> unit

val check_link : t -> [ `SPEED_10G | `SPEED_1G | `SPEED_100 | `SPEED_UNKNOWN ] * bool

module Memory = Memory
