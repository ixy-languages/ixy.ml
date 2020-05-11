let default_mtu = 1518

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

  let _10G_pma_pmd_shift = 7

  let _10G_xaui = 0x0 lsl _10G_pma_pmd_shift

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

  let mpe = 0x00000100 (* Multicast Promiscuous Enable *)

  let upe = 0x00000200 (* Unicast Promiscuous Enable *)

  let pe = mpe lor upe (* Promiscuous Enable *)
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

module LEDCTL = struct
  type t = int

  let mode_mask index = 0xF lsl (8 * index)

  let mode_shift index = 8 * index

  let led_on old index =
    let masked = old land (lnot (mode_mask index)) in
    masked lor (0xE lsl (mode_shift index))

  let led_off old index =
    let masked = old land (lnot (mode_mask index)) in
    masked lor (0xF lsl (mode_shift index))
end

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

type reg = int

let register_to_reg register =
  match register with
  | LINKS -> 0x042A4
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
  | LEDCTL -> 0x00200
  | GPRC -> 0x04074
  | GPTC -> 0x04080
  | GORCL -> 0x04088
  | GORCH -> 0x0408C
  | GOTCL -> 0x04090
  | GOTCH -> 0x04094
  | RAL i -> 0x0A200 + (i * 8)
  | RAH i -> 0x0A204 + (i * 8)

let register_to_string register =
  let open Printf in
  match register with
  | LINKS -> "LINKS"
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
  | LEDCTL -> "LEDCTL"
  | GPRC -> "GPRC"
  | GPTC -> "GPTC"
  | GORCL -> "GORCL"
  | GORCH -> "GORCH"
  | GOTCL -> "GOTCL"
  | GOTCH -> "GOTCH"
  | RAL i -> sprintf "RAL[%d]" i
  | RAH i -> sprintf "RAH[%d]" i
