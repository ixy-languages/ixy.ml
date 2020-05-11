open Lwt.Infix
open Mirage_net

module Make (Pci : Mirage_pci.S) = struct
  module Ixy = Ixy_core.Make (Pci_mirage.Make (Pci))

  type t = {
    dev : Ixy.t;
    mempool : Ixy_core.Ixy_memory.mempool;
    mutable active : bool
  }

  type error = [
    | Mirage_net.Net.error
    | `No_more_bufs of string
  ]

  let pp_error ppf = function
    | #Net.error as e -> Net.pp_error ppf e
    | `No_more_bufs addr -> Fmt.pf ppf "ixy %s: no more free bufs" addr

  let connect t =
    let dev = Ixy.create ~pci:t ~rxq:1 ~txq:1 in
    let mempool =
      Ixy.Memory.allocate_mempool dev.Ixy.pci ?pre_fill:None ~num_entries:2048 in
    Lwt.return { dev; mempool; active = true }

  let disconnect t =
    t.active <- false;
    Ixy.shutdown t.dev;
    Lwt.return_unit

  let mtu _ = 1500

  let lwt_ok_unit = Lwt.return_ok ()

  let write t ~size:_ fill =
    match Ixy.Memory.pkt_buf_alloc t.mempool with
    | None -> Lwt.return_error (`No_more_bufs t.dev.Ixy.pci_addr)
    | Some pkt ->
      let open Ixy_core.Ixy_memory in
      Cstruct.memset pkt.data 0;
      let len = fill pkt.data in
      if len > 1518 then
        Lwt.return_error `Invalid_length
      else begin
        Ixy.Memory.pkt_buf_resize pkt ~size:len;
        Ixy.tx_batch_busy_wait t.dev 0 [|pkt|];
        lwt_ok_unit
      end

  let listen t ~header_size cb =
    if header_size > 18 then
      Lwt.return_error `Invalid_length
    else
      let rec aux () =
        let recv pkt =
          let open Ixy_core.Ixy_memory in
          let buf = Cstruct.create pkt.size in
          Cstruct.blit pkt.data 0 buf 0 pkt.size;
          Ixy.Memory.pkt_buf_free pkt;
          Lwt.async (fun () -> cb buf);
          Lwt.return_unit in
        if t.active then
          let batch = Ixy.rx_batch t.dev 0 in
          begin
            if Array.length batch = 0 then
              Lwt.pause ()
            else
              Array.fold_left (fun acc v -> acc >>= fun () -> recv v) Lwt.return_unit batch
          end >>= aux
        else
          lwt_ok_unit in
      aux ()

  let mac { dev; _ } =
    Macaddr.of_octets_exn (Cstruct.to_string (Ixy.get_mac dev))

  let get_stats_counters { dev; _ } =
    let { Ixy.rx_pkts; tx_pkts; rx_bytes; tx_bytes } = Ixy.get_stats dev in
    { rx_pkts = Int32.of_int rx_pkts;
      tx_pkts = Int32.of_int tx_pkts;
      rx_bytes = Int64.of_int rx_bytes;
      tx_bytes = Int64.of_int tx_bytes
    }

  let reset_stats_counters { dev; _ } =
    Ixy.reset_stats dev
end
