module Make (Pci : Mirage_pci.S) = struct
  open Ixy_core.Ixy_pci
  include Pci

  let map_resource t =
    match Pci.bar0 t with
    | None -> failwith "bar0 not mapped"
    | Some cs -> cs.Cstruct.buffer

  let get_config t =
    { vendor = Pci.vendor_id t
    ; device_id = Pci.device_id t
    ; class_code = Pci.class_code t
    ; subclass = Pci.subclass_code t
    ; prog_if = Pci.progif t
    }

  let to_string t = Pci.name t

  let virt_to_phys buf = Ixy_core.Ixy_memory.int64_of_addr buf

  let allocated = ref 0

  let allocate_dma pci ?require_contiguous:_ size =
    try
      let offset = !allocated in
      (* TODO check address alignment *)
      allocated := !allocated + size;
      let virt = Cstruct.sub (Pci.dma pci) offset size in
      Some Ixy_core.Ixy_memory.{ virt; physical = virt_to_phys virt }
    with
    | Invalid_argument _ -> None
end
