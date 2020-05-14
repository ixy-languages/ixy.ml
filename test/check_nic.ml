open Ixy_core.Log

let usage () =
  error "Usage: %s <pci_addr>" Sys.argv.(0)

let () =
  if Array.length Sys.argv <> 2 then
    usage ();
  let pci =
    match Ixy.of_string Sys.argv.(1) with
    | None -> usage ()
    | Some pci -> pci in
  let dev = Ixy.create ~pci ~rxq:1 ~txq:1 in
  let mac = Ixy.get_mac dev in
  info
    "MAC: %02x:%02x:%02x:%02x:%02x:%02x\n"
    (Cstruct.get_uint8 mac 0)
    (Cstruct.get_uint8 mac 1)
    (Cstruct.get_uint8 mac 2)
    (Cstruct.get_uint8 mac 3)
    (Cstruct.get_uint8 mac 4)
    (Cstruct.get_uint8 mac 5);
  let speed, up = Ixy.check_link dev in
  begin
    match speed with
    | `SPEED_10G -> info "speed: 10G\n"
    | `SPEED_1G -> info "speed: 1G\n"
    | `SPEED_100 -> info "speed: 100\n"
    | `SPEED_UNKNOWN -> info "speed: UNKNOWN\n"
  end;
  info "up: %b\n" up
