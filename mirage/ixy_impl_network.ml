open Mirage

let connect_err name number =
  Fmt.strf "The %s connect expects exactly %d argument%s"
    name number (if number = 1 then "" else "s")

let ixy_conf = object
  inherit base_configurable
  method ty = pci @-> network
  method name = "ixy"
  method module_name = "Netif.Make"
  method! packages =
    Key.pure [ package "ixy-core" ; package "mirage-net-ixy" ]
  method! connect _ modname = function
    | [ pci ] -> Fmt.strf "%s.connect %s" modname pci
    | _ -> failwith (connect_err "ixy" 1)
end

let ixy_func = impl ixy_conf
let ixy_of_pci pci = ixy_func $ pci
