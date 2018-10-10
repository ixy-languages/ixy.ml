open Core

let () =
  let Ixy.PCI.{ vendor; device_id; class_code; subclass; prog_if } =
    Ixy.PCI.get_config Sys.argv.(1) in
  Ixy.Log.info
    "vendor: %#x device_id: %#x class_code: %#x subclass: %#x prog IF: %#x"
    vendor
    device_id
    class_code
    subclass
    prog_if
