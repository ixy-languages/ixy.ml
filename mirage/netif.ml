open Lwt.Infix
open Mirage_net

type +'a io = 'a Lwt.t

type t = {
  dev : Ixy.t;
  mempool : Ixy.Memory.mempool;
  mutable active : bool
}

type error = [
  | Mirage_net.Net.error
  | `No_more_bufs of string
]

let pp_error ppf = function
  | #Net.error as e -> Net.pp_error ppf e
  | `No_more_bufs addr -> Fmt.pf ppf "ixy %s: no more free bufs" addr

let connect pci_addr =
  match Ixy.PCI.of_string pci_addr with
  | None -> Lwt.fail_with ("could not parse " ^ pci_addr)
  | Some pci_addr ->
    let dev = Ixy.create ~pci_addr ~rxq:1 ~txq:1 in
    let mempool =
      Ixy.Memory.allocate_mempool ?pre_fill:None ~num_entries:2048 in
    Lwt.return { dev; mempool; active = true }

let disconnect t =
  t.active <- false;
  Ixy.shutdown t.dev;
  Lwt.return_unit

type macaddr = Macaddr.t

type buffer = Cstruct.t

let mtu _ = 1500

let lwt_ok_unit = Lwt.return_ok ()

let write t ~size:_ fill =
  match Ixy.Memory.pkt_buf_alloc t.mempool with
  | None -> Lwt.return_error (`No_more_bufs t.dev.pci_addr)
  | Some pkt ->
    Cstruct.memset pkt.data 0;
    let len = fill pkt.data in
    if len > 1518 then
      Lwt.return_error `Invalid_length
    else begin
      Ixy.Memory.pkt_buf_resize pkt ~size:len;
      Ixy.tx_batch_busy_wait t.dev 0 pkt.mempool [pkt];
      lwt_ok_unit
    end

let rec listen t ~header_size cb =
  if header_size > 18 then
    Lwt.return_error `Invalid_length
  else
    let aux pkt =
      let buf = Cstruct.create pkt.Ixy.Memory.size in
      Cstruct.blit pkt.data 0 buf 0 pkt.size;
      Ixy.Memory.pkt_buf_free pkt;
      Lwt.async (fun () -> cb buf);
      Lwt.return_unit in
    if t.active then
      let batch = Ixy.rx_batch t.dev 0 in
      begin
        if batch == [] then (* phys_equal because [] == 0 *)
          Lwt.pause ()
        else
          Lwt_list.iter_p aux batch
      end >>= fun () ->
      listen t ~header_size cb
    else
      lwt_ok_unit

let mac { dev; _ } =
  Macaddr.of_bytes_exn (Cstruct.to_string (Ixy.get_mac dev))

let get_stats_counters { dev; _ } =
  let { Ixy.rx_pkts; tx_pkts; rx_bytes; tx_bytes } = Ixy.get_stats dev in
  { rx_pkts = Int32.of_int rx_pkts;
    tx_pkts = Int32.of_int tx_pkts;
    rx_bytes = Int64.of_int rx_bytes;
    tx_bytes = Int64.of_int tx_bytes
  }

let reset_stats_counters { dev; _ } =
  Ixy.reset_stats dev
