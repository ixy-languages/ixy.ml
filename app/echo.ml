let usage () =
  Ixy.Log.error "Usage: %s <pci_addr>" Sys.argv.(0)

let () =
  if Array.length Sys.argv <> 2 then
    usage ();
  let pci_addr =
    match Ixy.PCI.of_string Sys.argv.(1) with
    | None -> usage ()
    | Some pci -> pci in
  let dev = Ixy.create ~pci_addr ~rxq:1 ~txq:1 in
  while true do
    let rx = Ixy.rx_batch dev 0 in
    let n = Array.length rx in
    if n > 0 then
      Ixy.Log.info "echoing %d packets" n;
    Ixy.tx_batch_busy_wait dev 0 rx;
  done
