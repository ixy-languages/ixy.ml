val max_queues : int (* maximum number of queues *)

module ADV_RXD : sig
  val stat_dd : int (* descriptor done *)

  val stat_eop : int (* end of packet *)
end

module ADV_TXD : sig
  val stat_dd : int

  val dcmd_eop : int

  val dcmd_rs : int

  val dcmd_ifcs : int

  val dcmd_dext : int

  val dtyp_data : int

  val paylen_shift : int
end

module EIMC : sig
  type t = int

  val interrupt_disable : t
end

module SPEED : sig
  type t = int

  val _10G : t (* 10 Gigabit/s *)

  val _1G : t (* 1 Gigabit/s *)

  val _100 : t (* 100 Megabit/s *)
end

module LINKS : sig
  type t = int

  val up : t

  val speed_82599 : t
end

module CTRL : sig
  type t = int

  val lnk_rst : t

  val rst : t

  val ctrl_rst_mask : t
end

module MACC : sig
  type t = int

  val flu : t

  val fsv : t

  val fs : t
end

module LEDCTL : sig
  type t = int

  type led = [ `LED0 | `LED1 | `LED2 | `LED3 ]

  val mode_mask : led -> int

  val mode_shift : led -> int

  val blink : led -> int

  val link_active : t
end

module EEC : sig
  type t = int

  val ard : t
end

module RDRXCTL : sig
  type t = int

  val dmaidone : t

  val crcstrip : t
end

module AUTOC : sig
  type t = int

  val lms_mask : t

  val lms_10G_serial : t

  val _10G_pma_pmd_mask : t

  val an_restart : t
end

module RXCTRL : sig
  type t = int

  val rxen : t
end

module RXPBSIZE : sig
  type t = int

  val _128KB : t
end

module HLREG0 : sig
  type t = int

  val txcrcen : t

  val rxcrcstrp : t

  val txpaden : t
end

module FCTRL : sig
  type t = int

  val bam : t
end

module SRRCTL : sig
  type t = int

  val desctype_mask : t

  val desctype_adv_onebuf : t

  val drop_en : t (* drop enable *)
end

module CTRL_EXT : sig
  type t = int

  val ns_dis : t
end

module RXDCTL : sig
  type t = int

  val enable : t
end

module TXPBSIZE : sig
  type t = int

  val _40KB : t
end

module RTTDCS : sig
  type t = int

  val arbdis : t (* DCB arbiter disable *)
end

module TXDCTL : sig
  type t = int

  val enable : t
end

module DMATXCTL : sig
  type t = int

  val te : t (* transmit enable *)
end

(* FIXME add custom type for every variant *)
(* FIXME reorder registers to allow sorting by offset range *)
type _ register =
  | LEDCTL : LEDCTL.t register (* LED control *)
  | LINKS : LINKS.t register (* link status *)
  | MACC : MACC.t register (* used in the linux ixgbe driver *)
  | EIMC : EIMC.t register (* extended interrupt mask clear *)
  | CTRL : CTRL.t register (* device control *)
  | CTRL_EXT : CTRL_EXT.t register (* extended device control *)
  | EEC : EEC.t register (* EEPROM flash control *)
  | RDRXCTL : RDRXCTL.t register (* receive DMA control *)
  | AUTOC : AUTOC.t register (* auto-negotiaton control *)
  | RXCTRL : RXCTRL.t register (* receive control *)
  | RXPBSIZE : int -> RXPBSIZE.t register (* receive packet buffer size *)
  | HLREG0 : HLREG0.t register (* MAC core control 0 *)
  | FCTRL : FCTRL.t register (* filter control *)
  | SRRCTL : int -> SRRCTL.t register (* split receive control *)
  | RDBAL : int -> int register (* receive descriptor base address low *)
  | RDBAH : int -> int register (* receive descriptor base address high *)
  | RDLEN : int -> int register (* receive descriptor length *)
  | RDH : int -> int register (* receive descriptor head *)
  | RDT : int -> int register (* receive descriptor tail *)
  | DCA_RXCTRL : int -> int register (* receive DCA control *)
  | RXDCTL : int -> RXDCTL.t register (* receive descriptor control *)
  | TXPBSIZE : int -> TXPBSIZE.t register (* transmit packet buffer size *)
  | DTXMXSZRQ : int register (* DMA tx TCP max allow size requests *)
  | RTTDCS : RTTDCS.t register (* DCB transmit descriptor plane control and status *)
  | TDBAL : int -> int register (* transmit descriptor base address low *)
  | TDBAH : int -> int register (* transmit descriptor base address high *)
  | TDLEN : int -> int register (* transmit descriptor length *)
  | TDH : int -> int register (* transmit descriptor head *)
  | TDT : int -> int register (* transmit descriptor tail *)
  | TXDCTL : int -> TXDCTL.t register (* transmit descriptor control *)
  | DMATXCTL : DMATXCTL.t register (* DMA tx control *)

val get_reg : PCI.hw -> 'a register -> int

val set_reg : PCI.hw -> 'a register -> 'a -> unit

val set_flags : PCI.hw -> 'a register -> 'a -> unit

val clear_flags : PCI.hw -> 'a register -> 'a -> unit

val wait_set : PCI.hw -> 'a register -> 'a -> unit

val wait_clear : PCI.hw -> 'a register -> 'a -> unit
