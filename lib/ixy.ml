open Core

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

let tx_clean_batch = 32

type rxq = {
  descriptors : RXD.t array; (** RX descriptor ring. *)
  mempool : Memory.mempool; (** [mempool] from which to allocate receive buffers. *)
  mutable rx_index : int; (** Descriptor ring tail pointer. *)
  pkt_bufs : Memory.pkt_buf array; (** [pkt_bufs.(i)] contains the buffer corresponding to [descriptors.(i)] for [0] <= [i] < [num_entries]. *)
}

type txq = {
  descriptors : TXD.t array; (** TX descriptor ring. *)
  mutable clean_index : int; (** Pointer to first unclean descriptor. *)
  mutable tx_index : int; (** Descriptor ring tail pointer. *)
  pkt_bufs : Memory.pkt_buf array; (** [pkt_bufs.(i)] contains the buffer corresponding to [descriptors.(i)] for [0] <= [i] < [num_entries]. Initially filled with [Memory.dummy]. *)
}

type register_access = {
  get_reg : IXGBE.register -> int32;
  set_reg : IXGBE.register -> int32 -> unit;
  set_flags : IXGBE.register -> int32 -> unit;
  clear_flags : IXGBE.register -> int32 -> unit;
  wait_set : IXGBE.register -> int32 -> unit;
  wait_clear : IXGBE.register -> int32 -> unit
}

type stats = {
  rx_pkts : int;
  tx_pkts : int;
  rx_bytes : int;
  tx_bytes : int
}

type t = {
  pci_addr : string;
  num_rxq : int;
  rxqs : rxq array;
  num_txq : int;
  txqs : txq array;
  ra : register_access;
  mutable rx_pkts : int;
  mutable tx_pkts : int;
  mutable rx_bytes : int;
  mutable tx_bytes : int
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
  ignore @@ Unix.nanosleep 0.01;
  info "reset done"

let init_link ra =
  let autoc = ra.get_reg IXGBE.AUTOC in
  ra.set_reg
    IXGBE.AUTOC
    Int32.((autoc land (lnot IXGBE.AUTOC.lms_mask)) lor IXGBE.AUTOC.lms_10G_serial);
  let autoc = ra.get_reg IXGBE.AUTOC in
  ra.set_reg
    IXGBE.AUTOC
    Int32.(autoc land (lnot IXGBE.AUTOC._10G_pma_pmd_mask));
  ra.set_flags IXGBE.AUTOC IXGBE.AUTOC.an_restart

let init_rx ra n =
  (* disable RX while configuring *)
  ra.clear_flags IXGBE.RXCTRL IXGBE.RXCTRL.rxen;
  if n > 0 then begin
    (* 128KB packet buffers *)
    ra.set_reg (IXGBE.RXPBSIZE 0) IXGBE.RXPBSIZE._128KB;
    for i = 1 to 7 do
      ra.set_reg (IXGBE.RXPBSIZE i) 0l
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
        Int32.((srrctl land (lnot IXGBE.SRRCTL.desctype_mask)) lor IXGBE.SRRCTL.desctype_adv_onebuf);
      (* drop packets if no rx descriptors available *)
      ra.set_flags (IXGBE.SRRCTL i) IXGBE.SRRCTL.drop_en;
      (* setup descriptor ring *)
      let ring_size_bytes =
        RXD.sizeof * num_rx_queue_entries in
      let descriptor_ring =
        Memory.allocate_dma ~require_contiguous:true ring_size_bytes in
      (* set all descriptor bytes to 0xFF to prevent memory problems *)
      Cstruct.memset descriptor_ring.virt 0xFF;
      let descriptors =
        RXD.split
          num_rx_queue_entries
          descriptor_ring.virt in
      (* set base address *)
      let lo, hi = Util.split descriptor_ring.phys in
      ra.set_reg (IXGBE.RDBAL i) lo;
      ra.set_reg (IXGBE.RDBAH i) hi;
      (* set ring length *)
      ra.set_reg (IXGBE.RDLEN i) (Int32.of_int_exn ring_size_bytes);
      debug "rx ring %d phy addr: %#018Lx" i descriptor_ring.phys;
      (* ring head = ring tail = 0
       * -> ring is empty
       * -> NIC won't write packets until we start the queue *)
      ra.set_reg (IXGBE.RDH i) 0l;
      ra.set_reg (IXGBE.RDT i) 0l;
      let mempool_size = num_rx_queue_entries + num_tx_queue_entries in
      let mempool =
        Memory.allocate_mempool
          ?pre_fill:None
          ~num_entries:(Int.max mempool_size 4096) in
      let pkt_bufs =
        Memory.pkt_buf_alloc_batch
          mempool
          ~num_bufs:num_rx_queue_entries in
      { descriptors;
        mempool;
        rx_index = 0;
        pkt_bufs
      } in
    let rxqs = Array.init n ~f:init_rxq in
    (* disable no snoop *)
    ra.set_flags IXGBE.CTRL_EXT IXGBE.CTRL_EXT.ns_dis;
    (* set magic bits *)
    for i = 0 to n - 1 do
      ra.clear_flags (IXGBE.DCA_RXCTRL i) Int32.(1l lsl 12)
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
  Array.iter2_exn
    rxq.descriptors
    rxq.pkt_bufs
    ~f:RXD.reset;
  t.ra.set_flags (IXGBE.RXDCTL i) IXGBE.RXDCTL.enable;
  t.ra.wait_set (IXGBE.RXDCTL i) IXGBE.RXDCTL.enable;
  t.ra.set_reg (IXGBE.RDH i) 0l; (* should already be 0l? *)
  t.ra.set_reg (IXGBE.RDT i) Int32.((of_int_exn num_rx_queue_entries) - 1l)

let init_tx ra n =
  if n > 0 then begin
    (* enable crc offload and small packet padding *)
    ra.set_flags IXGBE.HLREG0 Int32.(IXGBE.HLREG0.txcrcen lor IXGBE.HLREG0.txpaden);
    ra.set_reg (IXGBE.TXPBSIZE 0) IXGBE.TXPBSIZE._40KB;
    for i = 1 to 7 do
      ra.set_reg (IXGBE.TXPBSIZE i) 0l
    done;
    ra.set_reg IXGBE.DTXMXSZRQ 0xFFFFl;
    ra.clear_flags IXGBE.RTTDCS IXGBE.RTTDCS.arbdis;
    let init_txq i =
      debug "initializing txq %d" i;
      let ring_size_bytes =
        TXD.sizeof * num_tx_queue_entries in
      let descriptor_ring =
        Memory.allocate_dma ~require_contiguous:true ring_size_bytes in
      Cstruct.memset descriptor_ring.virt 0xff;
      (* set base address *)
      let lo, hi = Util.split descriptor_ring.phys in
      ra.set_reg (IXGBE.TDBAL i) lo;
      ra.set_reg (IXGBE.TDBAH i) hi;
      (* set ring length *)
      ra.set_reg (IXGBE.TDLEN i) Int32.(of_int_exn ring_size_bytes);
      debug "tx ring %d phy addr: %#018Lx" i descriptor_ring.phys;
      let txdctl_old =
        ra.get_reg (IXGBE.TXDCTL i) in
      let txdctl_magic_bits =
        let open Int32 in
        txdctl_old
        land ((lnot 0x3Fl) lor (0x3Fl lsl 8) lor (0x3Fl lsl 16))
        lor (36l lor (8l lsl 8) lor (4l lsl 16)) in
      ra.set_reg (IXGBE.TXDCTL i) txdctl_magic_bits;
      let descriptors =
        TXD.split
          num_tx_queue_entries
          descriptor_ring.virt in
      let pkt_bufs =
        Array.create num_tx_queue_entries Memory.dummy in
      { descriptors;
        clean_index = 0;
        tx_index = 0;
        pkt_bufs;
      } in
    let txqs = Array.init n ~f:init_txq in
    ra.set_reg IXGBE.DMATXCTL IXGBE.DMATXCTL.te;
    txqs
  end else
    [||]

let start_tx t i =
  info "starting txq %d" i;
  if num_tx_queue_entries land (num_tx_queue_entries - 1) <> 0 then
    error "number of tx queue entries must be a power of 2";
  t.ra.set_reg (IXGBE.TDH i) 0l;
  t.ra.set_reg (IXGBE.TDT i) 0l;
  t.ra.set_flags (IXGBE.TXDCTL i) IXGBE.TXDCTL.enable;
  t.ra.wait_set (IXGBE.TXDCTL i) IXGBE.TXDCTL.enable

let set_promisc t on =
  (if on then t.ra.set_flags else t.ra.clear_flags)
    IXGBE.FCTRL
    IXGBE.FCTRL.pe

let check_link t =
  let links_reg = t.ra.get_reg IXGBE.LINKS in
  let speed =
    match Int32.(links_reg land IXGBE.LINKS.speed_82599) with
    | speed when speed = IXGBE.SPEED._10G -> `SPEED_10G
    | speed when speed = IXGBE.SPEED._1G -> `SPEED_1G
    | speed when speed = IXGBE.SPEED._100 -> `SPEED_100
    | _ -> `SPEED_UNKNOWN in
  let link_up = Int32.(links_reg land IXGBE.LINKS.up <> 0l) in
  (speed, link_up)

let wait_for_link t =
  let max_wait = 10. in
  let poll_interval = 0.01 in
  let rec loop rem =
    let speed, _ = check_link t in
    match speed with
    | `SPEED_UNKNOWN ->
      if rem > 0. then begin
        ignore @@ Unix.nanosleep poll_interval;
        loop (rem -. poll_interval)
      end
    | `SPEED_10G ->
      info "Link speed is 10 Gbit/s"
    | `SPEED_1G ->
      info "Link speed is 1 Gbit/s"
    | `SPEED_100 ->
      info "Link speed is 100 Mbit/s" in
  loop max_wait

let get_stats t =
  t.rx_pkts <- t.rx_pkts + Int32.to_int_exn (t.ra.get_reg IXGBE.GPRC);
  t.tx_pkts <- t.tx_pkts + Int32.to_int_exn (t.ra.get_reg IXGBE.GPTC);
  let new_rx_bytes =
    Int32.to_int_exn (t.ra.get_reg IXGBE.GORCL)
    + (Int32.to_int_exn (t.ra.get_reg IXGBE.GORCH) lsl 32) in
  t.rx_bytes <- t.rx_bytes + new_rx_bytes;
  let new_tx_bytes =
    Int32.to_int_exn (t.ra.get_reg IXGBE.GOTCL)
    + (Int32.to_int_exn (t.ra.get_reg IXGBE.GOTCH) lsl 32) in
  t.tx_bytes <- t.tx_bytes + new_tx_bytes;
  { rx_pkts = t.rx_pkts;
    tx_pkts = t.tx_pkts;
    rx_bytes = t.rx_bytes;
    tx_bytes = t.tx_bytes
  }

let reset_stats t =
  ignore @@ get_stats t;
  t.rx_pkts <- 0;
  t.tx_pkts <- 0;
  t.rx_bytes <- 0;
  t.tx_bytes <- 0

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
    | 0x1, 0x0, 0x0, v when v = PCI.vendor_intel -> (* TODO make these errors *)
      warn "device %s is configured as SCSI storage device in EEPROM" pci_addr_str
    | 0x2, 0x0, _, v when v <> PCI.vendor_intel ->
      warn "device %s is a non-Intel NIC (vendor: %#x)" pci_addr_str vendor
    | 0x2, _, _, _ ->
      warn "device %s is not an Ethernet NIC (subclass: %#x)" pci_addr_str subclass
    | _ ->
      warn "device %s is not a NIC (class: %#x)" pci_addr_str class_code
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
    { pci_addr = pci_addr_str;
      num_rxq = rxq;
      rxqs = init_rx ra rxq;
      num_txq = txq;
      txqs = init_tx ra txq;
      ra;
      rx_pkts = 0;
      tx_pkts = 0;
      rx_bytes = 0;
      tx_bytes = 0
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

let rx_batch t rxq_id =
  let wrap_rx index =
    index land (num_rx_queue_entries - 1) in
  let { descriptors; pkt_bufs; mempool; _ } as rxq =
    t.rxqs.(rxq_id) in
  let num_done =
    let rec loop offset =
      let rxd = descriptors.(wrap_rx (rxq.rx_index + offset)) in
      if RXD.dd rxd then
        if not (RXD.eop rxd) then
          error "jumbo frames are not supported"
        else
          loop (offset + 1)
      else
        offset in
    loop 0 in
  let bufs =
    let empty_bufs =
      Memory.pkt_buf_alloc_batch mempool num_done in
    if Array.length empty_bufs <> num_done then
      error "could not allocate enough buffers";
    let receive offset =
      let index = wrap_rx (rxq.rx_index + offset) in
      debug "receiving at index %d" index;
      let buf, rxd = pkt_bufs.(index), descriptors.(index) in
      Memory.pkt_buf_resize buf (RXD.size rxd);
      let new_buf = empty_bufs.(offset) in
      RXD.reset rxd new_buf;
      pkt_bufs.(index) <- new_buf;
      buf in
    Array.init num_done ~f:receive in
  if num_done > 0 then begin
    rxq.rx_index <- wrap_rx (rxq.rx_index + num_done);
    t.ra.set_reg (IXGBE.RDT rxq_id) (Int32.of_int_exn (wrap_rx (rxq.rx_index - 1)))
  end;
  bufs

let tx_batch ?(clean_large = false) t txq_id bufs =
  let wrap_tx index =
    index land (num_tx_queue_entries - 1) in
  let { descriptors; pkt_bufs; _ } as txq = t.txqs.(txq_id) in
  (* returns wether or not the descriptor at clean_index + offset can be cleaned *)
  let check offset =
    let cleanable = wrap_tx (txq.tx_index - txq.clean_index) in
    cleanable >= offset && TXD.dd descriptors.(wrap_tx (txq.clean_index + offset - 1)) in
  let clean_ahead offset =
    (* cleanup_to points to the first descriptor we won't clean *)
    let cleanup_to =
      wrap_tx (txq.clean_index + offset - 1) in
    let rec loop i =
      Memory.pkt_buf_free pkt_bufs.(i);
      if i <> cleanup_to then
        loop (wrap_tx (i + 1)) in
    loop txq.clean_index;
    txq.clean_index <- wrap_tx (cleanup_to + 1) in
  if clean_large then begin
    if check 128 then (* possibly quicker batching *)
      clean_ahead 128
    else if check 64 then
      clean_ahead 64
    else if check 32 then
      clean_ahead 32
  end else
    while check tx_clean_batch do (* default ixy behavior *)
      clean_ahead tx_clean_batch
    done;
  let num_empty_descriptors =
    wrap_tx (txq.clean_index - txq.tx_index) in
  let n = Int.min num_empty_descriptors (Array.length bufs) in
  for i = 0 to n - 1 do
    (* send packet *)
    let index = wrap_tx (txq.tx_index + i) in
    TXD.reset descriptors.(index) bufs.(i);
    pkt_bufs.(index) <- bufs.(i)
  done;
  txq.tx_index <- wrap_tx (txq.tx_index + n);
  if n > 0 then
    debug "transmitted %d packets" n;
  t.ra.set_reg (IXGBE.TDT txq_id) (Int32.of_int_exn txq.tx_index);
  Array.sub bufs ~pos:n ~len:(Array.length bufs - n)

let tx_batch_busy_wait ?clean_large t txq_id bufs =
  let rec send bufs =
    let rest = tx_batch ?clean_large t txq_id bufs in
    if rest <> [||] then
      send rest in
  send bufs
