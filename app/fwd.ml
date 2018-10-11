let forward rx_dev tx_dev =
  let rx = Ixy.rx_batch rx_dev 0 in
  let rec loop rx =
    match Ixy.tx_batch tx_dev 0 rx with
    | [] -> ()
    | rest -> loop rest in
  let n = List.length rx in
  if n > 0 then
    Ixy.Log.info
      "forwarding %d packets from %s to %s"
      n
      rx_dev.pci_addr
      tx_dev.pci_addr;
  loop rx

let () =
  let dev_a = Ixy.create ~pci_addr:Sys.argv.(1) ~rxq:1 ~txq:1 in
  let dev_b = Ixy.create ~pci_addr:Sys.argv.(2) ~rxq:1 ~txq:1 in
  while true do
    forward dev_a dev_b;
    forward dev_b dev_a
  done
