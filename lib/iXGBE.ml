open Core

let max_queues = 64

module ADV_RXD = struct
  let stat_dd = 0x01

  let stat_eop = 0x02
end

module ADV_TXD = struct
  let stat_dd = 0x01

  let dcmd_eop = 0x01000000

  let dcmd_rs = 0x08000000

  let dcmd_ifcs = 0x02000000

  let dcmd_dext = 0x20000000

  let dtyp_data = 0x00300000

  let paylen_shift = 14
end

module EIMC = struct
  type t = int

  let interrupt_disable = 0x7FFFFFFF
end

module SPEED = struct
  type t = int

  let _10G = 0x30000000

  let _1G = 0x20000000

  let _100 = 0x10000000
end

module LINKS = struct
  type t = int

  let up = 0x40000000

  let speed_82599 = 0x30000000
end

module CTRL = struct
  type t = int

  let lnk_rst = 0x00000008

  let rst = 0x04000000

  let ctrl_rst_mask = lnk_rst lor rst
end

module MACC = struct
  type t = int

  let flu = 0x00000001

  let fsv = 0x00030000

  let fs = 0x00040000
end

module LEDCTL = struct
  type t = int

  type led = [ `LED0 | `LED1 | `LED2 | `LED3 ] [@@deriving enum]

  let mode_mask led =
    0x0000000F lsl (8 * (led_to_enum led))

  let mode_shift led =
    8 * (led_to_enum led)

  let blink led =
    0x00000080 lsl (8 * (led_to_enum led))

  let link_active = 0x4
end

module EEC = struct
  type t = int

  let ard = 0x00000200 (* EEPROM Auto Read Done *)
end

module RDRXCTL = struct
  type t = int

  let dmaidone = 0x00000008 (* DMA init cycle done *)

  let crcstrip = 0x00000002
end

module AUTOC = struct
  type t = int

  let lms_shift = 13

  let lms_mask = 0x7 lsl lms_shift

  let lms_10G_serial = 0x3 lsl lms_shift

  let _10G_pma_pmd_mask = 0x00000180

  let an_restart = 0x00001000
end

module RXCTRL = struct
  type t = int

  let rxen = 0x00000001
end

module RXPBSIZE = struct
  type t = int

  let _128KB = 0x00020000
end

module HLREG0 = struct
  type t = int

  let txcrcen = 0x00000001

  let rxcrcstrp = 0x00000002

  let txpaden = 0x00000400
end

module FCTRL = struct
  type t = int

  let bam = 0x00000400 (* Broadcast Accept Mode *)
end

module SRRCTL = struct
  type t = int

  let desctype_mask = 0x0E000000

  let desctype_adv_onebuf = 0x02000000

  let drop_en = 0x10000000
end

module CTRL_EXT = struct
  type t = int

  let ns_dis = 0x00010000
end

module RXDCTL = struct
  type t = int

  let enable = 0x02000000
end

module TXPBSIZE = struct
  type t = int

  let _40KB = 0x0000A000
end

module RTTDCS = struct
  type t = int

  let arbdis = 0x00000040
end

module TXDCTL = struct
  type t = int

  let enable = 0x02000000
end

module DMATXCTL = struct
  type t = int

  let te = 0x1
end

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

let register_to_int (type t) (register : t register) : int =
  match register with
  | LEDCTL -> 0x00200
  | LINKS -> 0x042A4
  | MACC -> 0x04330
  | EIMC -> 0x00888
  | CTRL -> 0x00000
  | CTRL_EXT -> 0x00018
  | EEC -> 0x10010
  | RDRXCTL -> 0x02F00
  | AUTOC -> 0x042A0
  | RXCTRL -> 0x03000
  | RXPBSIZE i -> 0x03C00 + (i * 4)
  | HLREG0 -> 0x04240
  | FCTRL -> 0x05080
  | SRRCTL i ->
    if i <= 15 then
      0x02100 + (i * 4)
    else if i < 64 then
      0x01014 + (i * 0x40)
    else
      0x0D014 + ((i - 64) * 0x40)
  | RDBAL i ->
    if i < 64 then
      0x01000 + (i * 0x40)
    else
      0x0D000 + ((i - 64) * 0x40)
  | RDBAH i ->
    if i < 64 then
      0x01004 + (i * 0x40)
    else
      0x0D004 + ((i - 64) * 0x40)
  | RDLEN i ->
    if i < 64 then
      0x01008 + (i * 0x40)
    else
      0x0D008 + ((i - 64) * 0x40)
  | RDH i ->
    if i < 64 then
      0x01010 + (i * 0x40)
    else
      0x0D010 + ((i - 64) * 0x40)
  | RDT i ->
    if i < 64 then
      0x01018 + (i * 0x40)
    else
      0x0D018 + ((i - 64) * 0x40)
  | DCA_RXCTRL i ->
    if i <= 15 then
      0x02200 + (i * 4)
    else if i < 64 then
      0x0100C + (i * 0x40)
    else
      0x0D00C + ((i - 64) * 0x40)
  | RXDCTL i ->
    if i < 64 then
      0x01028 + (i * 0x40)
    else
      0x0D028 + ((i - 64) * 0x40)
  | TXPBSIZE i -> 0x0CC00 + (i * 4)
  | DTXMXSZRQ -> 0x08100
  | RTTDCS -> 0x04900
  | TDBAL i -> 0x06000 + (i * 0x40)
  | TDBAH i -> 0x06004 + (i * 0x40)
  | TDLEN i -> 0x06008 + (i * 0x40)
  | TDH i -> 0x06010 + (i * 0x40)
  | TDT i -> 0x06018 + (i * 0x40)
  | TXDCTL i -> 0x06028 + (i * 0x40)
  | DMATXCTL -> 0x04A80

let register_to_string register =
  match register with
  | LEDCTL -> "LEDCTL"
  | LINKS -> "LINKS"
  | MACC -> "MACC"
  | EIMC -> "EIMC"
  | CTRL -> "CTRL"
  | CTRL_EXT -> "CTRL_EXT"
  | EEC -> "EEC"
  | RDRXCTL -> "RDRXCTL"
  | AUTOC -> "AUTOC"
  | RXCTRL -> "RXCTRL"
  | RXPBSIZE i -> sprintf "RXPBSIZE[%d]" i
  | HLREG0 -> "HLREG0"
  | FCTRL -> "FCTRL"
  | SRRCTL i -> sprintf "SRRCTL[%d]" i
  | RDBAL i -> sprintf "RDBAL[%d]" i
  | RDBAH i -> sprintf "RDBAH[%d]" i
  | RDLEN i -> sprintf "RDLEN[%d]" i
  | RDH i -> sprintf "RDH[%d]" i
  | RDT i -> sprintf "RDT[%d]" i
  | DCA_RXCTRL i -> sprintf "DCA_RXCTRL[%d]" i
  | RXDCTL i -> sprintf "RXDCTL[%d]" i
  | TXPBSIZE i -> sprintf "TXPBSIZE[%d]" i
  | DTXMXSZRQ -> "DTXMXSZRQ"
  | RTTDCS -> "RTTDCS"
  | TDBAL i -> sprintf "TDBAL[%d]" i
  | TDBAH i -> sprintf "TDBAH[%d]" i
  | TDLEN i -> sprintf "TDLEN[%d]" i
  | TDH i -> sprintf "TDH[%d]" i
  | TDT i -> sprintf "TDT[%d]" i
  | TXDCTL i -> sprintf "TXDCTL[%d]" i
  | DMATXCTL -> "DMATXCTL"

let get_reg (type t) hw (register : t register) : int =
  if Ixy_dbg.testing then
    0
  else
    Memory.read32 hw (register_to_int register)

(* TODO there has to be a better way to do this*)
let set_reg (type t) hw (register : t register) (v : t) =
  let register = (Obj.magic register : int register) in
  if Ixy_dbg.testing then
    ()
  else
    Memory.write32 hw (register_to_int register) (Obj.magic v : int)

let set_flags (type t) hw (register : t register) (flags : t) =
  let register = (Obj.magic register : int register) in
  if Ixy_dbg.testing then
    ()
  else
    set_reg hw register (get_reg hw register lor (Obj.magic flags : int))

let clear_flags (type t) hw (register : t register) (flags : t) =
  let register = (Obj.magic register : int register) in
  if Ixy_dbg.testing then
    ()
  else
    set_reg hw register (get_reg hw register lor (lnot (Obj.magic flags : int)))

let wait_set (type t) hw (reg : t register) (mask : t) =
  let reg = (Obj.magic reg : int register) in
  let mask = (Obj.magic mask : int) in
  if Ixy_dbg.testing then
    ()
  else
    while get_reg hw reg land mask <> mask do
      ignore @@ Unix.nanosleep 0.01;
      Log.debug
        "waiting for flags %#08X in reg %s(%#05Xr)"
        mask
        (register_to_string reg)
        (register_to_int reg)
    done

let wait_clear (type t) hw (reg : t register) (mask : t) =
  let reg = (Obj.magic reg : int register) in
  let mask = (Obj.magic mask : int) in
  if Ixy_dbg.testing then
    ()
  else
    while get_reg hw reg land mask <> 0 do
      ignore @@ Unix.nanosleep 0.01;
      Log.debug
        "waiting for flags %#08X in reg %s(%#05Xr)"
        mask
        (register_to_string reg)
        (register_to_int reg)
    done
