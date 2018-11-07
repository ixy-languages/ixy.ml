open Core

let () =
  let pci_addr =
    match Ixy.PCI.of_string Sys.argv.(1) with
    | None -> Ixy.Log.error "Usage: %s <pci_addr>" Sys.argv.(0)
    | Some pci -> pci in
  let ixy_dev =
    try Ixy.create ~pci_addr ~rxq:1 ~txq:1 with
    | Invalid_argument err ->
      Printf.printf "Error: %s\nUsage: %s PCI-ADDR\n" err Sys.argv.(0);
      exit 1 in
  let speed, up = Ixy.check_link ixy_dev in
  begin match speed with
  | `SPEED_10G -> Printf.printf "speed: 10G\n"
  | `SPEED_1G -> Printf.printf "speed: 1G\n"
  | `SPEED_100 -> Printf.printf "speed: 100\n"
  | `SPEED_UNKNOWN -> Printf.printf "speed: UNKNOWN\n"
  end;
  Printf.printf "up: %b\n" up;
  Ixy.reset ixy_dev
