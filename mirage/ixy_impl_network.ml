open Mirage

let connect_err name number =
  Fmt.strf "The %s connect expects exactly %d argument%s"
    name number (if number = 1 then "" else "s")

let ixy_conf =
  let packages = [ package "ixy-core"; package "mirage-net-ixy" ] in
  let connect _ modname = function
    | [ pci ] -> Fmt.strf "%s.connect %s" modname pci
    | _ -> failwith (connect_err "ixy" 1) in
  impl ~packages ~connect "Netif.Make" (pci @-> network)
let ixy_of_pci pci = ixy_conf $ pci
