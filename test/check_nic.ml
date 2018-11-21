open Core

let usage () =
  Ixy.Log.error "Usage: %s <pci_addr>" Sys.argv.(0)

let () =
  if Array.length Sys.argv <> 2 then
    usage ();
  let pci_addr =
    match Ixy.PCI.of_string Sys.argv.(1) with
    | None -> usage ()
    | Some pci -> pci in
  let dev = Ixy.create ~pci_addr ~rxq:1 ~txq:1 in
  let speed, up = Ixy.check_link dev in
  begin match speed with
  | `SPEED_10G -> Printf.printf "speed: 10G\n"
  | `SPEED_1G -> Printf.printf "speed: 1G\n"
  | `SPEED_100 -> Printf.printf "speed: 100\n"
  | `SPEED_UNKNOWN -> Printf.printf "speed: UNKNOWN\n"
  end;
  Printf.printf "up: %b\n" up;
  Ixy.reset dev
