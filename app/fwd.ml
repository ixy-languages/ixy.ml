let () =
  let src = Ixy.create ~pci_addr:Sys.argv.(1) ~rxq:1 ~txq:1 in
  let dst = Ixy.create ~pci_addr:Sys.argv.(2) ~rxq:1 ~txq:1 in
  while true do
    let rx = Ixy.rx_batch src 0 in
    let rec loop rx =
      match Ixy.tx_batch dst 0 rx with
      | [] -> ()
      | rest -> loop rest in
    let n = List.length rx in
    if n > 0 then
      Ixy.Log.info "forwarding %d packets" n;
    loop rx
  done
