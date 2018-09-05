open Core

let () =
  let Ixy.Memory.{ virt; phys } = Ixy.Memory.allocate_dma 10 in
  let ocaml = Ixy.Memory.virt_to_phys virt in
  let c = Ixy.Memory.c_virt_to_phys virt in
  Ixy.Log.info "ocaml: %#018Lx\nc: %#018Lx\ndma: %#018Lx\n" ocaml c phys;
  if ocaml = c then
    Ixy.Log.info "addresses match"
  else
    Ixy.Log.error "addresses don't match";
  let dev = Ixy.create ~pci_addr:"0000:00:00.0" ~rxq:1 ~txq:1 in
  ignore dev
