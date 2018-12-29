let forward rx_dev tx_dev =
  let rx = Ixy.rx_batch rx_dev 0 in
  (* touch all received packets *)
  Array.iter
    Ixy.Memory.(fun pkt ->
        Cstruct.(set_uint8 pkt.data 48 (1 + get_uint8 pkt.data 48)))
    rx;
  Ixy.tx_batch tx_dev 0 rx
  (* free packets that cannot be sent immediately *)
  |> Array.iter Ixy.Memory.pkt_buf_free

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
