let () =
  let pci =
    match Ixy.of_string Sys.argv.(1) with
    | None -> Ixy_core.Log.error "Usage: %s <pci_addr>" Sys.argv.(0)
    | Some pci -> pci in
  let Ixy_core.Ixy_pci.{ vendor; device_id; class_code; subclass; prog_if } =
    Ixy.Pci.get_config pci in
  Ixy_core.Log.info
    "vendor: %#x device_id: %#x class_code: %#x subclass: %#x prog IF: %#x"
    vendor
    device_id
    class_code
    subclass
    prog_if
