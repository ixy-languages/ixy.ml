module Main (S: Mirage_pci.S) = struct
  module Ixy = Ixy_core.Make (Pci_mirage.Make (S))

  let start pci0 =
    let dev = Ixy.create ~pci:pci0 ~rxq:1 ~txq:1 in
    while true do
      let rx = Ixy.rx_batch dev 0 in
      Ixy.tx_batch_busy_wait dev 0 rx;
    done;
    Lwt.return_unit
end
