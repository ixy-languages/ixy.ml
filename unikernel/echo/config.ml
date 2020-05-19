open Mirage

let main = foreign "Unikernel.Main" (pci @-> job)

let pci0 =
  let device_info : device_info =
    { vendor_id = 0x8086
    ; device_id = 0x10fb
    ; class_code = 0x2
    ; subclass_code = 0x0
    ; progif = 0x0
    ; dma_size = 16777216
    ; bus_master_enable = true
    ; map_bar0 = true
    ; map_bar1 = false
    ; map_bar2 = false
    ; map_bar3 = false
    ; map_bar4 = false
    ; map_bar5 = false
    } in
  pcidev device_info "pci0"

let () =
  register "echo" [
    main $ pci0
  ] ~packages:[ package "ixy-core"; package "mirage-net-ixy" ]
