val max_queues : int

module SPEED_ : sig
  val _10G : int

  val _1G : int

  val _100 : int
end

module LINKS_ : sig
  val up : int

  val speed_82599 : int
end

module CTRL_ : sig
  val lnk_rst : int

  val rst : int

  val ctrl_rst_mask : int
end

module MACC_ : sig
  val flu : int

  val fsv : int

  val fs : int
end

module LED_ : sig
  type led = [ `LED0 | `LED1 | `LED2 | `LED3 ]

  val mode_mask : led -> int

  val mode_shift : led -> int

  val blink : led -> int

  val link_active : int
end

module EEC : sig
  type t = int

  val ard : t
end

module RDRXCTL_ : sig
  val dmaidone : int

  val crcstrip : int
end

module AUTOC_ : sig
  val lms_mask : int

  val lms_10G_serial : int

  val _10G_pma_pmd_mask : int

  val an_restart : int
end

module RXCTRL_ : sig
  val rxen : int
end

module RXPBSIZE_ : sig
  val _128KB : int
end

module HLREG0_ : sig
  val txcrcen : int

  val rxcrcstrp : int

  val txpaden : int
end

module FCTRL_ : sig
  val bam : int
end

module SRRCTL_ : sig
  val desctype_mask : int

  val desctype_adv_onebuf : int

  val drop_en : int
end

(* FIXME add custom type for every variant *)
type _ register =
  | LEDCTL : int register
  | LINKS : int register
  | MACC : int register
  | EIMC : int register
  | CTRL : int register
  | EEC : EEC.t register
  | RDRXCTL : int register
  | AUTOC : int register
  | RXCTRL : int register
  | RXPBSIZE : int -> int register
  | HLREG0 : int register
  | FCTRL : int register
  | SRRCTL : int -> int register
  | RDBAL : int -> int register
  | RDBAH : int -> int register
  | RDLEN : int -> int register
  | RDH : int -> int register
  | RDT : int -> int register

val get_reg : Pci.hw -> 'a register -> int

val set_reg : Pci.hw -> 'a register -> 'a -> unit

val set_flags : Pci.hw -> 'a register -> 'a -> unit

val clear_flags : Pci.hw -> 'a register -> 'a -> unit

val wait_set : Pci.hw -> 'a register -> 'a -> unit

val wait_clear : Pci.hw -> 'a register -> 'a -> unit
