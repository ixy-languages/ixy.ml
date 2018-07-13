open Core

let max_queues = 64

module SPEED_ = struct
  let _10G = 0x30000000

  let _1G = 0x20000000

  let _100 = 0x10000000
end

module LINKS_ = struct
  let up = 0x40000000

  let speed_82599 = 0x30000000
end

module CTRL_ = struct
  let lnk_rst = 0x00000008

  let rst = 0x04000000

  let ctrl_rst_mask = lnk_rst lor rst
end

module MACC_ = struct
  let flu = 0x00000001

  let fsv = 0x00030000

  let fs = 0x00040000
end

module LED_ = struct
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

module RDRXCTL_ = struct
  let dmaidone = 0x00000008 (* DMA init cycle done *)

  let crcstrip = 0x00000002
end

module AUTOC_ = struct
  let lms_shift = 13

  let lms_mask = 0x7 lsl lms_shift

  let lms_10G_serial = 0x3 lsl lms_shift

  let _10G_pma_pmd_mask = 0x00000180

  let an_restart = 0x00001000
end

module RXCTRL_ = struct
  let rxen = 0x00000001
end

module RXPBSIZE_ = struct
  let _128KB = 0x00020000
end

module HLREG0_ = struct
  let txcrcen = 0x00000001

  let rxcrcstrp = 0x00000002

  let txpaden = 0x00000400
end

module FCTRL_ = struct
  let bam = 0x00000400 (* Broadcast Accept Mode *)
end

module SRRCTL_ = struct
  let desctype_mask = 0x0E000000

  let desctype_adv_onebuf = 0x02000000

  let drop_en = 0x10000000
end

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

let register_to_int (type t) (register : t register) : int =
  match register with
  | LEDCTL -> 0x00200
  | LINKS -> 0x042A4
  | MACC -> 0x04330
  | EIMC -> 0x00888
  | CTRL -> 0x00000
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

let get_reg (type t) hw (register : t register) : int =
  Memory.read32 hw (register_to_int register)

let set_reg (type t) hw (register : t register) (v : t) =
  match register with
  | LEDCTL -> Memory.write32 hw (register_to_int register) v
  | LINKS -> Memory.write32 hw (register_to_int register) v
  | MACC -> Memory.write32 hw (register_to_int register) v
  | EIMC -> Memory.write32 hw (register_to_int register) v
  | CTRL -> Memory.write32 hw (register_to_int register) v
  | EEC -> Memory.write32 hw (register_to_int register) v
  | RDRXCTL -> Memory.write32 hw (register_to_int register) v
  | AUTOC -> Memory.write32 hw (register_to_int register) v
  | RXCTRL -> Memory.write32 hw (register_to_int register) v
  | RXPBSIZE i -> Memory.write32 hw (register_to_int register) v
  | HLREG0 -> Memory.write32 hw (register_to_int register) v
  | FCTRL -> Memory.write32 hw (register_to_int register) v
  | SRRCTL i -> Memory.write32 hw (register_to_int register) v
  | RDBAL i -> Memory.write32 hw (register_to_int register) v
  | RDBAH i -> Memory.write32 hw (register_to_int register) v
  | RDLEN i -> Memory.write32 hw (register_to_int register) v
  | RDH i -> Memory.write32 hw (register_to_int register) v
  | RDT i -> Memory.write32 hw (register_to_int register) v

let set_flags (type t) hw (register : t register) (flags : t) =
  match register with
  | LEDCTL -> set_reg hw register (get_reg hw register lor flags)
  | LINKS -> set_reg hw register (get_reg hw register lor flags)
  | MACC -> set_reg hw register (get_reg hw register lor flags)
  | EIMC -> set_reg hw register (get_reg hw register lor flags)
  | CTRL -> set_reg hw register (get_reg hw register lor flags)
  | EEC -> set_reg hw register (get_reg hw register lor flags)
  | RDRXCTL -> set_reg hw register (get_reg hw register lor flags)
  | AUTOC -> set_reg hw register (get_reg hw register lor flags)
  | RXCTRL -> set_reg hw register (get_reg hw register lor flags)
  | RXPBSIZE i -> set_reg hw register (get_reg hw register lor flags)
  | HLREG0 -> set_reg hw register (get_reg hw register lor flags)
  | FCTRL -> set_reg hw register (get_reg hw register lor flags)
  | SRRCTL i -> set_reg hw register (get_reg hw register lor flags)
  | RDBAL i -> set_reg hw register (get_reg hw register lor flags)
  | RDBAH i -> set_reg hw register (get_reg hw register lor flags)
  | RDLEN i -> set_reg hw register (get_reg hw register lor flags)
  | RDH i -> set_reg hw register (get_reg hw register lor flags)
  | RDT i -> set_reg hw register (get_reg hw register lor flags)

let clear_flags (type t) hw (register : t register) (flags : t) =
  match register with
  | LEDCTL -> set_reg hw register (get_reg hw register lor (lnot flags))
  | LINKS -> set_reg hw register (get_reg hw register lor (lnot flags))
  | MACC -> set_reg hw register (get_reg hw register lor (lnot flags))
  | EIMC -> set_reg hw register (get_reg hw register lor (lnot flags))
  | CTRL -> set_reg hw register (get_reg hw register lor (lnot flags))
  | EEC -> set_reg hw register (get_reg hw register lor (lnot flags))
  | RDRXCTL -> set_reg hw register (get_reg hw register lor (lnot flags))
  | AUTOC -> set_reg hw register (get_reg hw register lor (lnot flags))
  | RXCTRL -> set_reg hw register (get_reg hw register lor (lnot flags))
  | RXPBSIZE i -> set_reg hw register (get_reg hw register lor (lnot flags))
  | HLREG0 -> set_reg hw register (get_reg hw register lor (lnot flags))
  | FCTRL -> set_reg hw register (get_reg hw register lor (lnot flags))
  | SRRCTL i -> set_reg hw register (get_reg hw register lor (lnot flags))
  | RDBAL i -> set_reg hw register (get_reg hw register lor (lnot flags))
  | RDBAH i -> set_reg hw register (get_reg hw register lor (lnot flags))
  | RDLEN i -> set_reg hw register (get_reg hw register lor (lnot flags))
  | RDH i -> set_reg hw register (get_reg hw register lor (lnot flags))
  | RDT i -> set_reg hw register (get_reg hw register lor (lnot flags))

let wait_set (type t) hw (reg : t register) (mask : t) =
  match reg with
  | LEDCTL ->
    while get_reg hw reg land mask <> mask do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | LINKS ->
    while get_reg hw reg land mask <> mask do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | MACC ->
    while get_reg hw reg land mask <> mask do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | EIMC ->
    while get_reg hw reg land mask <> mask do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | CTRL ->
    while get_reg hw reg land mask <> mask do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | EEC ->
    while get_reg hw reg land mask <> mask do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | RDRXCTL ->
    while get_reg hw reg land mask <> mask do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | AUTOC ->
    while get_reg hw reg land mask <> mask do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | RXCTRL ->
    while get_reg hw reg land mask <> mask do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | RXPBSIZE i ->
    while get_reg hw reg land mask <> mask do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | HLREG0 ->
    while get_reg hw reg land mask <> mask do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | FCTRL ->
    while get_reg hw reg land mask <> mask do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | SRRCTL i ->
    while get_reg hw reg land mask <> mask do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | RDBAL i ->
    while get_reg hw reg land mask <> mask do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | RDBAH i ->
    while get_reg hw reg land mask <> mask do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | RDLEN i ->
    while get_reg hw reg land mask <> mask do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | RDH i ->
    while get_reg hw reg land mask <> mask do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | RDT i ->
    while get_reg hw reg land mask <> mask do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done

let wait_clear (type t) hw (reg : t register) (mask : t) =
  match reg with
  | LEDCTL ->
    while get_reg hw reg land mask <> 0 do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | LINKS ->
    while get_reg hw reg land mask <> 0 do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | MACC ->
    while get_reg hw reg land mask <> 0 do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | EIMC ->
    while get_reg hw reg land mask <> 0 do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | CTRL ->
    while get_reg hw reg land mask <> 0 do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | EEC ->
    while get_reg hw reg land mask <> 0 do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | RDRXCTL ->
    while get_reg hw reg land mask <> 0 do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | AUTOC ->
    while get_reg hw reg land mask <> 0 do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | RXCTRL ->
    while get_reg hw reg land mask <> 0 do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | RXPBSIZE i ->
    while get_reg hw reg land mask <> 0 do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | HLREG0 ->
    while get_reg hw reg land mask <> 0 do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | FCTRL ->
    while get_reg hw reg land mask <> 0 do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | SRRCTL i ->
    while get_reg hw reg land mask <> 0 do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | RDBAL i ->
    while get_reg hw reg land mask <> 0 do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | RDBAH i ->
    while get_reg hw reg land mask <> 0 do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | RDLEN i ->
    while get_reg hw reg land mask <> 0 do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | RDH i ->
    while get_reg hw reg land mask <> 0 do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
  | RDT i ->
    while get_reg hw reg land mask <> 0 do
      Caml.Unix.sleepf 0.01; (* Core dropped sleepf for some reason *)
      Log.debug "waiting for flags %#08X in reg %#05Xr" mask (register_to_int reg)
    done
