let forward rx_dev tx_dev =
  let rx = Ixy.rx_batch rx_dev 0 in
  let n = Array.length rx in
  if n > 0 then
    Ixy.Log.info
      "forwarding %d packets from %s to %s"
      n
      rx_dev.Ixy.pci_addr
      tx_dev.Ixy.pci_addr;
  Ixy.tx_batch_busy_wait tx_dev 0 rx

let usage () =
  Ixy.Log.error "Usage: %s <pci_addr> <pci_addr>" Sys.argv.(0)

let () =
  if Array.length Sys.argv <> 3 then
    usage ();
  let pci_a, pci_b =
    match Ixy.PCI.(of_string Sys.argv.(1), of_string Sys.argv.(2)) with
    | None, _ | _, None -> usage ()
    | Some a, Some b -> a, b in
  let dev_a = Ixy.create ~pci_addr:pci_a ~rxq:1 ~txq:1 in
  let dev_b = Ixy.create ~pci_addr:pci_b ~rxq:1 ~txq:1 in
  while true do
    forward dev_a dev_b;
    forward dev_b dev_a
  done
