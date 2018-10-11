let () =
  if Array.length Sys.argv <> 2 then
    Ixy.Log.error "Usage: %s <pci_addr>" Sys.argv.(0);
  let dev = Ixy.create ~pci_addr:Sys.argv.(1) ~rxq:1 ~txq:1 in
  while true do
    let rx = Ixy.rx_batch dev 0 in
    let rec loop rx =
      match Ixy.tx_batch dev 0 rx with
      | [] -> ()
      | rest -> loop rest in
    let n = List.length rx in
    if n > 0 then
      Ixy.Log.info "echoing %d packets" n;
    loop rx
  done
