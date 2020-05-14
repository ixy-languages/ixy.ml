open Ixy_core.Log

let () =
  if Array.length Sys.argv <> 2 then
    error "Usage: %s <pci_addr>" Sys.argv.(0);
  match Ixy.of_string Sys.argv.(1) with
  | None ->
    error "could not parse PCI address"
  | Some addr ->
    info "parsed '%s'" (Ixy.Pci.to_string addr)
