open Core

let () =
  let Ixy.Memory.{ virt; phy } = Ixy.Memory.allocate_dma 10 in
  let ocaml = Ixy.Memory.virt_to_phys virt in
  let c = Ixy.Memory.c_virt_to_phys virt in
  Printf.printf "ocaml: %#018Lx\nc: %#018Lx\ndma: %#018Lx\n" ocaml c phy
