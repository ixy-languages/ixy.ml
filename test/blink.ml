open Ixy_core.Log
open Ixy_core

let usage () =
  error "Usage: %s <pci_addr> <index> [on|off]" Sys.argv.(0)

let () =
  if Array.length Sys.argv <> 4 then
    usage ();
  let pci =
    match Ixy.of_string Sys.argv.(1) with
    | None -> usage ()
    | Some pci -> pci in
  let index =
    match int_of_string Sys.argv.(2) with
    | i when i >= 0 && i <= 3 -> i
    | _ -> warn "0 <= index <= 3 not fulfilled"; usage ()
    | exception Failure _ -> warn "index not an integer"; usage () in
  let on =
    match String.lowercase_ascii Sys.argv.(3) with
    | "on" -> true
    | "off" -> false
    | _ -> warn "LEDs can only be turned on or off"; usage () in
  let hw = Ixy.Pci.map_resource pci in
  let led_old = Ixy_core.get_reg hw IXGBE.LEDCTL in
  debug "LEDCTL = %#x" led_old;
  let led_new =
    IXGBE.LEDCTL.(if on then led_on else led_off) led_old index in
  debug "LEDCTL := %#x" led_new;
  Ixy_core.set_reg hw IXGBE.LEDCTL led_new
