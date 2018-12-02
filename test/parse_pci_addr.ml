let () =
  if Array.length Sys.argv <> 2 then
    Ixy.Log.error "Usage: %s <pci_addr>" Sys.argv.(0);
  match Ixy.PCI.of_string Sys.argv.(1) with
  | None ->
    Ixy.Log.error "could not parse PCI address"
  | Some addr ->
    Ixy.Log.info "parsed '%s'" (Ixy.PCI.to_string addr)
