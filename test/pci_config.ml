open Core

let () =
  let pci_addr =
    match Ixy.PCI.of_string Sys.argv.(1) with
    | None -> Ixy.Log.error "Usage: %s <pci_addr>" Sys.argv.(0)
    | Some pci -> pci in
  let Ixy.PCI.{ vendor; device_id; class_code; subclass; prog_if } =
    Ixy.PCI.get_config pci_addr in
  Ixy.Log.info
    "vendor: %#x device_id: %#x class_code: %#x subclass: %#x prog IF: %#x"
    vendor
    device_id
    class_code
    subclass
    prog_if
