open Log

module Memory = Memory

module Uname = Uname

module Log = Log

module PCI = PCI

module IXGBE = IXGBE

let max_queues = 64

let max_rx_queue_entries = 4096
let max_tx_queue_entries = 4096

let num_rx_queue_entries = 512
let num_tx_queue_entries = 512

external ( < ) : 'a -> 'a -> bool = "%lessthan"
external ( <= ) : 'a -> 'a -> bool = "%lessequal"
external ( > ) : 'a -> 'a -> bool = "%greaterthan"
external ( >= ) : 'a -> 'a -> bool = "%greaterequal"

let ( > ) (x : int) y = x > y [@@inline]
let ( <= ) (x : int) y = x <= y [@@inline]
let ( < ) (x : int) y = x < y [@@inline]
let ( >= ) (x : int) y = x >= y [@@inline]

let min (a : int) b = if a <= b then a else b [@@inline]

module RXD = struct
  [@@@ocaml.warning "-32"]

  type t = Cstruct.t

  [%%cstruct
    type adv_rxd_read = {
      pkt_addr : uint64;
      hdr_addr : uint64
    } [@@little_endian]
  ]

  [%%cstruct
    type adv_rxd_wb = {
      pkt_info : uint16;
      hdr_info : uint16;
      ip_id : uint16;
      csum : uint16;
      status : uint16; (* Cstruct.uint16 is unboxed and therefore faster *)
      error : uint16;
      length : uint16;
      vlan : uint16
    } [@@little_endian]
  ]

  let () = assert (sizeof_adv_rxd_wb = sizeof_adv_rxd_read)

  let sizeof = sizeof_adv_rxd_wb

  let dd t =
    let status = get_adv_rxd_wb_status t in
    let stat_dd, stat_eop = 0b01, 0b10 in
    match status land (stat_dd lor stat_eop) with
    | 0b11 -> true
    | 0b01 -> error "jumbo frames are not supported"
    | _ -> false [@@inline]

  let size t = get_adv_rxd_wb_length t [@@inline]

  let split num cs =
    let len = Cstruct.len cs in
    if num * sizeof > len then
      error "cstruct is too small (%d bytes) for %d descriptors" len num;
    Array.init
      num
      (fun i -> Cstruct.sub cs (i * sizeof) sizeof)

  let reset cs Memory.{ phys; _ } =
    set_adv_rxd_read_pkt_addr cs phys;
    set_adv_rxd_read_hdr_addr cs 0L [@@inline]
end

module TXD = struct
  [@@@ocaml.warning "-32"]

  type t = Cstruct.t

  [%%cstruct
    type adv_tx_read = {
      buffer_addr : uint64;
      cmd_type_len : uint32;
      olinfo_status : uint32
    } [@@little_endian]
  ]

  [%%cstruct
    type adv_tx_wb = {
      rsvd : uint64;
      nxtseq_seed : uint32;
      status : uint16; (* Cstruct.uint16 is unboxed and therefore faster *)
      more_rsvd : uint16
    } [@@little_endian]
  ]

  let () = assert (sizeof_adv_tx_wb = sizeof_adv_tx_read)

  let sizeof = sizeof_adv_tx_wb

  let dd t =
    let stat_dd = 0b1 in
    (get_adv_tx_wb_status t) land stat_dd <> 0 [@@inline]

  let split num cs =
    let len = Cstruct.len cs in
    if num * sizeof > len then
      error "cstruct is too small (%d bytes) for %d descriptors" len num;
    Array.init
      num
      (fun i -> Cstruct.sub cs (i * sizeof) sizeof)

  let const_part =
    let dcmd_eop = 0x01000000 in
    let dcmd_rs = 0x08000000 in
    let dcmd_ifcs = 0x02000000 in
    let dcmd_dext = 0x20000000 in
    let dtyp_data = 0x00300000 in
    dcmd_eop lor dcmd_rs lor dcmd_ifcs lor dcmd_dext lor dtyp_data

  let reset cs Memory.{ size; phys; _ } =
    set_adv_tx_read_buffer_addr cs phys;
    set_adv_tx_read_cmd_type_len
      cs
      (Int32.of_int (const_part lor size));
    let paylen_shift = 14 in
    set_adv_tx_read_olinfo_status
      cs
      (Int32.of_int (size lsl paylen_shift)) [@@inline]
end

type rxq = {
  rdt : IXGBE.reg;
  rxds : RXD.t array;
  mempool : Memory.mempool;
  mutable rx_index : int;
  rx_bufs : Memory.pkt_buf array
}

type txq = {
  tdt : IXGBE.reg;
  txds : TXD.t array;
  mutable clean_index : int;
  mutable tx_index : int;
  tx_bufs : Memory.pkt_buf array
}

type register_access = {
  get_reg : IXGBE.register -> int;
  set_reg : IXGBE.register -> int -> unit;
  set_flags : IXGBE.register -> int -> unit;
  clear_flags : IXGBE.register -> int -> unit;
  wait_set : IXGBE.register -> int -> unit;
  wait_clear : IXGBE.register -> int -> unit
}

type stats = {
  mutable rx_pkts : int;
  mutable tx_pkts : int;
  mutable rx_bytes : int;
  mutable tx_bytes : int
}

type t = {
  hw : PCI.hw;
  pci_addr : string;
  num_rxq : int;
  rxqs : rxq array;
  num_txq : int;
  txqs : txq array;
  ra : register_access;
  stats : stats
}

let () =
  if Sys.os_type <> "Unix" || Uname.sysname <> "Linux" then
    error "ixy.ml only works on Linux"
  else if Sys.word_size <> 64 then
    error "ixy.ml only works on 64 bit systems"
  else if Sys.big_endian then
    error "ixy.ml only works on little endian systems"

let disable_interrupts ra =
  info "disabling interrupts";
  ra.set_reg IXGBE.EIMC IXGBE.EIMC.interrupt_disable

let reset ra =
  info "resetting";
  ra.set_reg IXGBE.CTRL IXGBE.CTRL.ctrl_rst_mask;
  ra.wait_clear IXGBE.CTRL IXGBE.CTRL.ctrl_rst_mask;
  Unix.sleepf 0.01;
  info "reset done"

let init_link ra =
  let autoc = ra.get_reg IXGBE.AUTOC in
  ra.set_reg
    IXGBE.AUTOC
    ((autoc land (lnot IXGBE.AUTOC.lms_mask)) lor IXGBE.AUTOC.lms_10G_serial);
  let autoc = ra.get_reg IXGBE.AUTOC in
  ra.set_reg
    IXGBE.AUTOC
    ((autoc land (lnot IXGBE.AUTOC._10G_pma_pmd_mask)) lor IXGBE.AUTOC._10G_xaui);
  ra.set_flags IXGBE.AUTOC IXGBE.AUTOC.an_restart

let init_rx ra n =
  (* disable RX while configuring *)
  ra.clear_flags IXGBE.RXCTRL IXGBE.RXCTRL.rxen;
  if n > 0 then begin
    (* 128KB packet buffers *)
    ra.set_reg (IXGBE.RXPBSIZE 0) IXGBE.RXPBSIZE._128KB;
    for i = 1 to 7 do
      ra.set_reg (IXGBE.RXPBSIZE i) 0
    done;
    (* enable CRC offload *)
    ra.set_flags IXGBE.HLREG0 IXGBE.HLREG0.rxcrcstrp;
    ra.set_flags IXGBE.RDRXCTL IXGBE.RDRXCTL.crcstrip;
    (* accept broadcast *)
    ra.set_flags IXGBE.FCTRL IXGBE.FCTRL.bam;
    let init_rxq i =
      debug "initializing rxq %d" i;
      (* enable advanced descriptors *)
      let srrctl = ra.get_reg (IXGBE.SRRCTL i) in
      ra.set_reg
        (IXGBE.SRRCTL i)
        ((srrctl land (lnot IXGBE.SRRCTL.desctype_mask)) lor IXGBE.SRRCTL.desctype_adv_onebuf);
      (* drop packets if no rx descriptors available *)
      ra.set_flags (IXGBE.SRRCTL i) IXGBE.SRRCTL.drop_en;
      (* setup descriptor ring *)
      let ring_size_bytes =
        RXD.sizeof * num_rx_queue_entries in
      let descriptor_ring =
        Memory.allocate_dma ~require_contiguous:true ring_size_bytes in
      (* set all descriptor bytes to 0xFF to prevent memory problems *)
      Cstruct.memset descriptor_ring.Memory.virt 0xFF;
      let rxds =
        RXD.split
          num_rx_queue_entries
          descriptor_ring.Memory.virt in
      (* set base address *)
      let lo, hi = Util.split descriptor_ring.Memory.physical in
      ra.set_reg (IXGBE.RDBAL i) lo;
      ra.set_reg (IXGBE.RDBAH i) hi;
      (* set ring length *)
      ra.set_reg (IXGBE.RDLEN i) ring_size_bytes;
      debug "rx ring %d phy addr: %#018Lx" i descriptor_ring.Memory.physical;
      (* ring head = ring tail = 0
       * -> ring is empty
       * -> NIC won't write packets until we start the queue *)
      ra.set_reg (IXGBE.RDH i) 0;
      ra.set_reg (IXGBE.RDT i) 0;
      let mempool_size = num_rx_queue_entries + num_tx_queue_entries in
      let mempool =
        Memory.allocate_mempool
          ?pre_fill:None
          ~num_entries:(max mempool_size 4096) in
      let rx_bufs =
        Memory.pkt_buf_alloc_batch
          mempool
          ~num_bufs:num_rx_queue_entries in
      { rdt = IXGBE.(register_to_reg @@ RDT i);
        rxds;
        mempool;
        rx_index = 0;
        rx_bufs
      } in
    let rxqs = Array.init n init_rxq in
    (* disable no snoop *)
    ra.set_flags IXGBE.CTRL_EXT IXGBE.CTRL_EXT.ns_dis;
    (* set magic bits *)
    for i = 0 to n - 1 do
      ra.clear_flags (IXGBE.DCA_RXCTRL i) (1 lsl 12)
    done;
    ra.set_flags IXGBE.RXCTRL IXGBE.RXCTRL.rxen;
    rxqs
  end else
    [||]

let start_rx t i =
  info "starting rxq %d" i;
  let rxq = t.rxqs.(i) in
  if num_tx_queue_entries land (num_rx_queue_entries - 1) <> 0 then
    error "number of rx queue entries must be a power of 2";
  (* reset all descriptors *)
  Array.iter2
    RXD.reset
    rxq.rxds
    rxq.rx_bufs;
  t.ra.set_flags (IXGBE.RXDCTL i) IXGBE.RXDCTL.enable;
  t.ra.wait_set (IXGBE.RXDCTL i) IXGBE.RXDCTL.enable;
  t.ra.set_reg (IXGBE.RDH i) 0; (* should already be 0? *)
  t.ra.set_reg (IXGBE.RDT i) (pred num_rx_queue_entries)

let init_tx ra n =
  if n > 0 then begin
    (* enable crc offload and small packet padding *)
    ra.set_flags
      IXGBE.HLREG0
      (IXGBE.HLREG0.txcrcen lor IXGBE.HLREG0.txpaden);
    ra.set_reg (IXGBE.TXPBSIZE 0) IXGBE.TXPBSIZE._40KB;
    for i = 1 to 7 do
      ra.set_reg (IXGBE.TXPBSIZE i) 0
    done;
    ra.set_reg IXGBE.DTXMXSZRQ 0xFFFF;
    ra.clear_flags IXGBE.RTTDCS IXGBE.RTTDCS.arbdis;
    let init_txq i =
      debug "initializing txq %d" i;
      let ring_size_bytes =
        TXD.sizeof * num_tx_queue_entries in
      let descriptor_ring =
        Memory.allocate_dma ~require_contiguous:true ring_size_bytes in
      Cstruct.memset descriptor_ring.Memory.virt 0xff;
      (* set base address *)
      let lo, hi = Util.split descriptor_ring.Memory.physical in
      ra.set_reg (IXGBE.TDBAL i) lo;
      ra.set_reg (IXGBE.TDBAH i) hi;
      (* set ring length *)
      ra.set_reg (IXGBE.TDLEN i) ring_size_bytes;
      debug "tx ring %d phy addr: %#018Lx" i descriptor_ring.Memory.physical;
      let txdctl_old =
        ra.get_reg (IXGBE.TXDCTL i) in
      let txdctl_magic_bits =
        (txdctl_old land ((lnot 0x3F) lor ((0x3F lsl 8) lor (0x3F lsl 16))))
        lor (36 lor ((8 lsl 8) lor (4 lsl 16))) in
      ra.set_reg (IXGBE.TXDCTL i) txdctl_magic_bits;
      let txds =
        TXD.split
          num_tx_queue_entries
          descriptor_ring.Memory.virt in
      let tx_bufs =
        Array.make num_tx_queue_entries Memory.dummy in
      { tdt = IXGBE.(register_to_reg @@ TDT i);
        txds;
        clean_index = 0;
        tx_index = 0;
        tx_bufs;
      } in
    let txqs = Array.init n init_txq in
    ra.set_reg IXGBE.DMATXCTL IXGBE.DMATXCTL.te;
    txqs
  end else
    [||]

let start_tx t i =
  info "starting txq %d" i;
  if num_tx_queue_entries land (num_tx_queue_entries - 1) <> 0 then
    error "number of tx queue entries must be a power of 2";
  t.ra.set_reg (IXGBE.TDH i) 0;
  t.ra.set_reg (IXGBE.TDT i) 0;
  t.ra.set_flags (IXGBE.TXDCTL i) IXGBE.TXDCTL.enable;
  t.ra.wait_set (IXGBE.TXDCTL i) IXGBE.TXDCTL.enable

let set_promisc t on =
  (if on then t.ra.set_flags else t.ra.clear_flags)
    IXGBE.FCTRL
    IXGBE.FCTRL.pe

let check_link t =
  let links_reg = t.ra.get_reg IXGBE.LINKS in
  let speed =
    match links_reg land IXGBE.LINKS.speed_82599 with
    | speed when speed = IXGBE.SPEED._10G -> `SPEED_10G
    | speed when speed = IXGBE.SPEED._1G -> `SPEED_1G
    | speed when speed = IXGBE.SPEED._100 -> `SPEED_100
    | _ -> `SPEED_UNKNOWN in
  let link_up = links_reg land IXGBE.LINKS.up <> 0 in
  (speed, link_up)

let wait_for_link t =
  let max_wait = 10. in
  let poll_interval = 0.01 in
  let rec loop rem =
    match check_link t with
    | _, false
    | `SPEED_UNKNOWN, _ ->
      if Float.compare rem 0. > 0 then begin
        Unix.sleepf poll_interval;
        loop (rem -. poll_interval)
      end
    | `SPEED_10G, true ->
      info "Link speed is 10 Gbit/s"
    | `SPEED_1G, true ->
      info "Link speed is 1 Gbit/s"
    | `SPEED_100, true ->
      info "Link speed is 100 Mbit/s" in
  loop max_wait

let get_stats t =
  let { stats; ra; _ } = t in
  stats.rx_pkts <- stats.rx_pkts + ra.get_reg IXGBE.GPRC;
  stats.tx_pkts <- stats.tx_pkts + ra.get_reg IXGBE.GPTC;
  let new_rx_bytes =
    (ra.get_reg IXGBE.GORCL) + ((ra.get_reg IXGBE.GORCH) lsl 32) in
  stats.rx_bytes <- stats.rx_bytes + new_rx_bytes;
  let new_tx_bytes =
    (ra.get_reg IXGBE.GOTCL) + ((ra.get_reg IXGBE.GOTCH) lsl 32) in
  stats.tx_bytes <- stats.tx_bytes + new_tx_bytes;
  stats

let get_mac t =
  let mac = Cstruct.create 6 in
  let low = t.ra.get_reg (IXGBE.RAL 0) in
  let high = t.ra.get_reg (IXGBE.RAH 0) in
  Cstruct.LE.set_uint32 mac 0 (Int32.of_int low);
  Cstruct.LE.set_uint16 mac 4 high;
  mac

let reset_stats t =
  ignore @@ get_stats t;
  let stats = t.stats in
  stats.rx_pkts <- 0;
  stats.tx_pkts <- 0;
  stats.rx_bytes <- 0;
  stats.tx_bytes <- 0

let create ~pci_addr ~rxq ~txq =
  if Unix.getuid () <> 0 then
    warn "not running as root, this will probably fail";
  if rxq > max_queues then
    error "cannot configure %d rx queues (max: %d)" rxq max_queues;
  if txq > max_queues then
    error "cannot configure %d tx queues (max: %d)" txq max_queues;
  let PCI.{ vendor; device_id; class_code; subclass; prog_if } =
    PCI.get_config pci_addr in
  let pci_addr_str = PCI.to_string pci_addr in
  begin match class_code, subclass, prog_if, vendor with
    | 0x2, 0x0, 0x0, v when v = PCI.vendor_intel -> ()
    | 0x1, 0x0, 0x0, v when v = PCI.vendor_intel ->
      error
        "device %s is configured as SCSI storage device in EEPROM"
        pci_addr_str
    | 0x2, 0x0, _, v when v <> PCI.vendor_intel ->
      error
        "device %s is a non-Intel NIC (vendor: %#x)"
        pci_addr_str
        vendor
    | 0x2, _, _, _ ->
      error
        "device %s is not an Ethernet NIC (subclass: %#x)"
        pci_addr_str
        subclass
    | _ ->
      error
        "device %s is not a NIC (class: %#x)"
        pci_addr_str
        class_code
  end;
  info "device %s has device id %#x" pci_addr_str device_id;
  let hw =
    PCI.map_resource pci_addr in
  let ra =
    { get_reg = IXGBE.get_reg hw;
      set_reg = IXGBE.set_reg hw;
      set_flags = IXGBE.set_flags hw;
      clear_flags = IXGBE.clear_flags hw;
      wait_set = IXGBE.wait_set hw;
      wait_clear = IXGBE.wait_clear hw
    } in
  disable_interrupts ra;
  reset ra;
  disable_interrupts ra;
  info "initializing device %s" pci_addr_str;
  ra.wait_set IXGBE.EEC IXGBE.EEC.ard;
  ra.wait_set IXGBE.RDRXCTL IXGBE.RDRXCTL.dmaidone;
  init_link ra;
  let t =
    { hw;
      pci_addr = pci_addr_str;
      num_rxq = rxq;
      rxqs = init_rx ra rxq;
      num_txq = txq;
      txqs = init_tx ra txq;
      ra;
      stats = { rx_pkts = 0; tx_pkts = 0; rx_bytes = 0; tx_bytes = 0 }
    } in
  reset_stats t;
  for i = 0 to rxq - 1 do
    start_rx t i
  done;
  for i = 0 to txq - 1 do
    start_tx t i
  done;
  set_promisc t true;
  wait_for_link t;
  t

let shutdown t =
  info "shutting down device %s" t.pci_addr;
  let shutdown_rx i _rxq =
    info "shutting down rxq %d" i;
    t.ra.clear_flags (IXGBE.RXDCTL i) IXGBE.RXDCTL.enable;
    t.ra.wait_clear (IXGBE.RXDCTL i) IXGBE.RXDCTL.enable;
    Unix.sleepf 0.0001 in
  let shutdown_tx i txq =
    info "shutting down txq %d" i;
    debug "waiting for %s" IXGBE.(register_to_string (TDH i));
    while t.ra.get_reg (IXGBE.TDH i) <> txq.tx_index do
      Unix.sleepf 0.01
    done;
    debug "done waiting";
    t.ra.clear_flags (IXGBE.TXDCTL i) IXGBE.TXDCTL.enable;
    t.ra.wait_clear (IXGBE.TXDCTL i) IXGBE.TXDCTL.enable in
  Array.iteri shutdown_rx t.rxqs;
  Array.iteri shutdown_tx t.txqs

let rx_batch ?(batch_size = max_int) t rxq_id =
  let wrap_rx index =
    index land (num_rx_queue_entries - 1) [@@inline] in
  let { rdt; rxds; rx_bufs; mempool; _ } as rxq =
    t.rxqs.(rxq_id) in
  let num_done =
    let rec loop offset =
      let rxd = rxds.(wrap_rx (rxq.rx_index + offset)) in
      if offset < batch_size && (RXD.dd [@inlined]) rxd then
        loop (offset + 1)
      else
        offset in
    loop 0 in
  let bufs =
    let empty_bufs =
      Memory.pkt_buf_alloc_batch mempool ~num_bufs:num_done in
    if Array.length empty_bufs <> num_done then
      error "could not allocate enough buffers";
    let receive offset =
      let index = wrap_rx (rxq.rx_index + offset) in
      let buf, rxd = rx_bufs.(index), rxds.(index) in
      buf.Memory.size <- (RXD.size [@inlined]) rxd;
      let new_buf = empty_bufs.(offset) in
      (RXD.reset [@inlined]) rxd new_buf;
      rx_bufs.(index) <- new_buf;
      buf [@@inline] in
    Array.init num_done receive in
  if num_done > 0 then begin
    rxq.rx_index <- wrap_rx (rxq.rx_index + num_done);
    IXGBE.set_reg_fast t.hw rdt (wrap_rx (rxq.rx_index - 1))
  end;
  bufs

let tx_batch t txq_id bufs =
  let wrap_tx index =
    index land (num_tx_queue_entries - 1) [@@inline] in
  let { tdt; txds; tx_bufs; _ } as txq = t.txqs.(txq_id) in
  let clean_batch = 32 in
  (* Returns wether or not clean_batch descriptors can be cleaned. *)
  let check_clean () =
    let cleanable = wrap_tx (txq.tx_index - txq.clean_index) in
    cleanable >= clean_batch
    && (TXD.dd [@inlined]) txds.(wrap_tx (txq.clean_index + clean_batch - 1)) [@@inline] in
  let clean () =
    for i = 0 to clean_batch - 1 do
      let buf = tx_bufs.(wrap_tx (txq.clean_index + i)) in
      let mempool = buf.Memory.mempool in
      mempool.Memory.free_bufs.(mempool.Memory.free) <- buf;
      mempool.Memory.free <- mempool.Memory.free + 1
    done;
    txq.clean_index <- wrap_tx (txq.clean_index + clean_batch) [@@inline] in
  while (check_clean [@inlined]) () do
    (clean [@inlined]) ()
  done;
  let num_empty_descriptors =
    wrap_tx (txq.clean_index - txq.tx_index - 1) in
  let n = min num_empty_descriptors (Array.length bufs) in
  for i = 0 to n - 1 do
    (* send packet *)
    let index = wrap_tx (txq.tx_index + i) in
    (TXD.reset [@inlined]) txds.(index) bufs.(i);
    tx_bufs.(index) <- bufs.(i)
  done;
  txq.tx_index <- wrap_tx (txq.tx_index + n);
  IXGBE.set_reg_fast t.hw tdt txq.tx_index;
  Array.sub bufs n (Array.length bufs - n)

let tx_batch_busy_wait t txq_id bufs =
  let rec send bufs =
    let rest = tx_batch t txq_id bufs in
    if Array.length rest <> 0 then
      send rest in
  send bufs
