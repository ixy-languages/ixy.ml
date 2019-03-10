let forward batch_size rx_dev tx_dev =
  let rx = Ixy.rx_batch ?batch_size rx_dev 0 in
  (* touch all received packets *)
  let rec touch = function
    | [] -> ()
    | hd :: tl ->
      match hd.Ixy.Memory.data with
      | None -> assert false
      | Some data ->
        Cstruct.(set_uint8 data 48 (1 + get_uint8 data 48));
        touch tl in
  touch rx;
  Ixy.tx_batch tx_dev 0 rx
  (* free packets that cannot be sent immediately *)
  |> List.iter Ixy.Memory.pkt_buf_give_to_mempool

let usage () =
  Ixy.Log.error "Usage: %s <pci_addr> <pci_addr> [batch_size]" Sys.argv.(0)

let () =
  let argc = Array.length Sys.argv in
  if argc < 3 || argc > 4 then
    usage ();
  let pci_a, pci_b =
    match Ixy.PCI.(of_string Sys.argv.(1), of_string Sys.argv.(2)) with
    | None, _ | _, None -> usage ()
    | Some a, Some b -> a, b in
  let dev_a = Ixy.create ~pci_addr:pci_a ~rxq:1 ~txq:1 in
  let dev_b = Ixy.create ~pci_addr:pci_b ~rxq:1 ~txq:1 in
  let batch_size =
    try Some (int_of_string Sys.argv.(3)) with
    | Invalid_argument _
    | Failure _ -> None in
  while true do
    forward batch_size dev_a dev_b;
    forward batch_size dev_b dev_a
  done
