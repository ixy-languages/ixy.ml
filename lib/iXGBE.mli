val default_mtu : int

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

  val _10G_xaui : t

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

  val pe : t
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

module LEDCTL : sig
  type t = int

  val led_on : int -> int -> t

  val led_off : int -> int -> t
end

(* FIXME reorder registers to allow sorting by offset range *)
type register =
  | LINKS (* link status *)
  | EIMC (* extended interrupt mask clear *)
  | CTRL (* device control *)
  | CTRL_EXT (* extended device control *)
  | EEC (* EEPROM flash control *)
  | RDRXCTL (* receive DMA control *)
  | AUTOC (* auto-negotiaton control *)
  | RXCTRL (* receive control *)
  | RXPBSIZE of int(* receive packet buffer size *)
  | HLREG0 (* MAC core control 0 *)
  | FCTRL (* filter control *)
  | SRRCTL of int (* split receive control *)
  | RDBAL of int (* receive descriptor base address low *)
  | RDBAH of int (* receive descriptor base address high *)
  | RDLEN of int (* receive descriptor length *)
  | RDH of int (* receive descriptor head *)
  | RDT of int (* receive descriptor tail *)
  | DCA_RXCTRL of int (* receive DCA control *)
  | RXDCTL of int (* receive descriptor control *)
  | TXPBSIZE of int (* transmit packet buffer size *)
  | DTXMXSZRQ (* DMA tx TCP max allow size requests *)
  | RTTDCS (* DCB transmit descriptor plane control and status *)
  | TDBAL of int (* transmit descriptor base address low *)
  | TDBAH of int (* transmit descriptor base address high *)
  | TDLEN of int (* transmit descriptor length *)
  | TDH of int (* transmit descriptor head *)
  | TDT of int (* transmit descriptor tail *)
  | TXDCTL of int (* transmit descriptor control *)
  | DMATXCTL (* DMA tx control *)
  | LEDCTL (* LED control *)
  | GPRC (* Good Packets Received Count *)
  | GPTC (* Good Packets Transmitted Count *)
  | GORCL (* Good Octets Received Count Low *)
  | GORCH (* Good Octets Received Count High *)
  | GOTCL (* Good Octets Transmitted Count Low *)
  | GOTCH (* Good Octets Transmitted Count High *)
  | RAL of int (* Receive Address Low *)
  | RAH of int (* Receive Address High *)

type reg

val register_to_reg : register -> reg

val register_to_string : register -> string
