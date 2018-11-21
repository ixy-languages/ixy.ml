open Core

open Log

module Memory = Memory

module Uname = Uname

module Log = Log

module PCI = PCI

let max_rx_queue_entries = 4096
let max_tx_queue_entries = 4096

let num_rx_queue_entries = 512
let num_tx_queue_entries = 512

let tx_clean_batch = 32

let rx_descriptor_bytes = 16
let tx_descriptor_bytes = 16

type rxq = {
  descriptors : RXD.t array; (** RX descriptor ring. *)
  mempool : Memory.mempool; (** [mempool] from which to allocate receive buffers. *)
  num_entries : int; (** Number of descriptors in the ring. *)
  mutable rx_index : int; (** Descriptor ring tail pointer. *)
  pkt_bufs : Memory.pkt_buf array; (** [pkt_bufs.(i)] contains the buffer corresponding to [descriptors.(i)] for [0] <= [i] < [num_entries]. *)
}

type txq = {
  descriptors : TXD.t array; (** TX descriptor ring. *)
  num_entries : int; (** Number of descriptors in the ring. *)
  mutable clean_index : int; (** Pointer to first unclean descriptor. *)
  mutable tx_index : int; (** Descriptor ring tail pointer. *)
  pkt_bufs : Memory.pkt_buf array; (** [pkt_bufs.(i)] contains the buffer corresponding to [descriptors.(i)] for [0] <= [i] < [num_entries]. Initially filled with [Memory.dummy]. *)
}

type t = {
  hw : PCI.hw;
  pci_addr : string;
  num_rxq : int;
  mutable rxqs : rxq array; (* TODO mutability needed? *)
  num_txq : int;
  mutable txqs : txq array;
  get_reg : IXGBE.register -> int32;
  set_reg : IXGBE.register -> int32 -> unit;
  set_flags : IXGBE.register -> int32 -> unit;
  clear_flags : IXGBE.register -> int32 -> unit;
  wait_set : IXGBE.register -> int32 -> unit;
  wait_clear : IXGBE.register -> int32 -> unit
}

let () =
  if Sys.os_type <> "Unix" || Uname.sysname <> "Linux" then
    error "ixy.ml only works on Linux"
  else if Sys.word_size <> 64 then
    error "ixy.ml only works on 64 bit systems"
  else if Sys.big_endian then
    error "ixy.ml only works on little endian systems"

let disable_interrupts t =
  info "disabling interrupts";
  t.set_reg IXGBE.EIMC IXGBE.EIMC.interrupt_disable

let reset t =
  info "resetting device %s" t.pci_addr;
  t.set_reg IXGBE.CTRL IXGBE.CTRL.ctrl_rst_mask;
  t.wait_clear IXGBE.CTRL IXGBE.CTRL.ctrl_rst_mask;
  ignore @@ Unix.nanosleep 0.01;
  info "reset done"

let init_link t =
  let autoc = t.get_reg IXGBE.AUTOC in
  t.set_reg
    IXGBE.AUTOC
    Int32.((autoc land (lnot IXGBE.AUTOC.lms_mask)) lor IXGBE.AUTOC.lms_10G_serial);
  let autoc = t.get_reg IXGBE.AUTOC in
  t.set_reg
    IXGBE.AUTOC
    Int32.(autoc land (lnot IXGBE.AUTOC._10G_pma_pmd_mask));
  t.set_flags IXGBE.AUTOC IXGBE.AUTOC.an_restart

(* TODO make this return an rxq *)
let init_rx t =
  (* disable RX while configuring *)
  t.clear_flags IXGBE.RXCTRL IXGBE.RXCTRL.rxen;
  if t.num_rxq > 0 then begin
    (* 128KB packet buffers *)
    t.set_reg (IXGBE.RXPBSIZE 0) IXGBE.RXPBSIZE._128KB;
    for i = 1 to 7 do
      t.set_reg (IXGBE.RXPBSIZE i) 0l
    done;
    (* enable CRC offload *)
    t.set_flags IXGBE.HLREG0 IXGBE.HLREG0.rxcrcstrp;
    t.set_flags IXGBE.RDRXCTL IXGBE.RDRXCTL.crcstrip;
    (* accept broadcast *)
    t.set_flags IXGBE.FCTRL IXGBE.FCTRL.bam;
    (* descriptor is 16 bytes in size *)
    let rxqs =
      Array.init
        t.num_rxq
        ~f:(fun i -> 
            debug "initializing rxq %d" i;
            (* enable advanced descriptors *)
            let srrctl = t.get_reg (IXGBE.SRRCTL i) in
            t.set_reg
              (IXGBE.SRRCTL i)
              Int32.((srrctl land (lnot IXGBE.SRRCTL.desctype_mask)) lor IXGBE.SRRCTL.desctype_adv_onebuf);
            (* drop packets if no rx descriptors available *)
            t.set_flags (IXGBE.SRRCTL i) IXGBE.SRRCTL.drop_en;
            (* setup descriptor ring *)
            let ring_size_bytes =
              rx_descriptor_bytes * num_rx_queue_entries in
            let descriptor_ring =
              Memory.allocate_dma ~require_contiguous:true ring_size_bytes in
            (* set all descriptor bytes to 0xFF to prevent memory problems *)
            Cstruct.memset descriptor_ring.virt 0xFF;
            let descriptors =
              RXD.split
                num_rx_queue_entries
                descriptor_ring.virt in
            (* set base address *)
            t.set_reg (IXGBE.RDBAL i) Int64.(to_int32_exn @@ descriptor_ring.phys land 0xFFFFFFFFL);
            t.set_reg (IXGBE.RDBAH i) Int64.(to_int32_exn @@ descriptor_ring.phys lsr 32);
            (* set ring length *)
            t.set_reg (IXGBE.RDLEN i) (Int32.of_int_exn ring_size_bytes);
            debug "rx ring %d phy addr: %#018Lx" i descriptor_ring.phys;
            (* ring head = ring tail = 0
             * -> ring is empty
             * -> NIC won't write packets until we start the queue *)
            t.set_reg (IXGBE.RDH i) 0l;
            t.set_reg (IXGBE.RDT i) 0l;
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
              num_entries = num_rx_queue_entries;
              rx_index = 0;
              pkt_bufs
            }
          ) in
    (* disable no snoop *)
    t.set_flags IXGBE.CTRL_EXT IXGBE.CTRL_EXT.ns_dis;
    (* set magic bits *)
    for i = 0 to t.num_rxq - 1 do
      t.clear_flags (IXGBE.DCA_RXCTRL i) Int32.(1l lsl 12)
    done;
    t.set_flags IXGBE.RXCTRL IXGBE.RXCTRL.rxen; (* warum hier? *)
    t.rxqs <- rxqs
  end

let start_rx t i =
  info "starting rxq %d" i;
  let rxq = t.rxqs.(i) in
  if rxq.num_entries land (rxq.num_entries - 1) <> 0 then
    error "number of rx queue entries must be a power of 2";
  (* reset all descriptors *)
  Array.iter2_exn
    rxq.descriptors
    rxq.pkt_bufs
    ~f:RXD.reset;
  t.set_flags (IXGBE.RXDCTL i) IXGBE.RXDCTL.enable;
  t.wait_set (IXGBE.RXDCTL i) IXGBE.RXDCTL.enable;
  t.set_reg (IXGBE.RDH i) 0l;
  t.set_reg (IXGBE.RDT i) Int32.((of_int_exn rxq.num_entries) - 1l)

let init_tx t =
  if t.num_txq > 0 then begin
    (* enable crc offload and small packet padding *)
    t.set_flags IXGBE.HLREG0 Int32.(IXGBE.HLREG0.txcrcen lor IXGBE.HLREG0.txpaden);
    t.set_reg (IXGBE.TXPBSIZE 0) IXGBE.TXPBSIZE._40KB;
    for i = 1 to 7 do
      t.set_reg (IXGBE.TXPBSIZE i) 0l
    done;
    t.set_reg IXGBE.DTXMXSZRQ 0xFFFFl;
    t.clear_flags IXGBE.RTTDCS IXGBE.RTTDCS.arbdis;
    let txqs =
      Array.init
        t.num_txq
        ~f:(fun i ->
            debug "initializing txq %d" i;
            let ring_size_bytes =
              num_tx_queue_entries * tx_descriptor_bytes in
            let descriptor_ring =
              Memory.allocate_dma ~require_contiguous:true ring_size_bytes in
            Cstruct.memset descriptor_ring.virt 0xff;
            (* set base address *)
            t.set_reg (IXGBE.TDBAL i) Int64.(to_int32_exn @@ descriptor_ring.phys land 0xFFFFFFFFL);
            t.set_reg (IXGBE.TDBAH i) Int64.(to_int32_exn @@ descriptor_ring.phys lsr 32);
            (* set ring length *)
            t.set_reg (IXGBE.TDLEN i) Int32.(of_int_exn ring_size_bytes);
            debug "tx ring %d phy addr: %#018Lx" i descriptor_ring.phys;
            let txdctl_old =
              t.get_reg (IXGBE.TXDCTL i) in
            let txdctl_magic_bits =
              let open Int32 in
              txdctl_old
              land ((lnot 0x3Fl) lor (0x3Fl lsl 8) lor (0x3Fl lsl 16))
              lor (36l lor (8l lsl 8) lor (4l lsl 16)) in
            t.set_reg (IXGBE.TXDCTL i) txdctl_magic_bits;
            let descriptors =
              TXD.split
                num_tx_queue_entries
                descriptor_ring.virt in
            let pkt_bufs = (* maybe fill with null buffers to avoid indirections *)
              Array.create num_tx_queue_entries Memory.dummy in
            { descriptors;
              num_entries = num_tx_queue_entries;
              clean_index = 0;
              tx_index = 0;
              pkt_bufs;
            }) in
    t.set_reg IXGBE.DMATXCTL IXGBE.DMATXCTL.te;
    t.txqs <- txqs
  end

let start_tx t i =
  info "starting txq %d" i;
  let txq = t.txqs.(i) in
  if txq.num_entries land (txq.num_entries - 1) <> 0 then
    error "number of tx queue entries must be a power of 2";
  t.set_reg (IXGBE.TDH i) 0l;
  t.set_reg (IXGBE.TDT i) 0l;
  t.set_flags (IXGBE.TXDCTL i) IXGBE.TXDCTL.enable;
  t.wait_set (IXGBE.TXDCTL i) IXGBE.TXDCTL.enable

let create ~pci_addr ~rxq ~txq =
  if Unix.getuid () <> 0 then
    warn "not running as root, this will probably fail";
  if rxq > IXGBE.max_queues then
    error "cannot configure %d rx queues (max: %d)" rxq IXGBE.max_queues;
  if txq > IXGBE.max_queues then
    error "cannot configure %d tx queues (max: %d)" txq IXGBE.max_queues;
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
  let t =
    { hw;
      pci_addr = pci_addr_str;
      num_rxq = rxq;
      rxqs = [||];
      num_txq = txq;
      txqs = [||];
      get_reg = IXGBE.get_reg hw;
      set_reg = IXGBE.set_reg hw;
      set_flags = IXGBE.set_flags hw;
      clear_flags = IXGBE.clear_flags hw;
      wait_set = IXGBE.wait_set hw;
      wait_clear = IXGBE.wait_clear hw
    } in
  disable_interrupts t;
  reset t;
  disable_interrupts t;
  info "initializing device %s" t.pci_addr;
  t.wait_set IXGBE.EEC IXGBE.EEC.ard;
  t.wait_set IXGBE.RDRXCTL IXGBE.RDRXCTL.dmaidone;
  init_link t;
  (* read_stats *)
  init_rx t;
  init_tx t;
  for i = 0 to rxq - 1 do
    start_rx t i
  done;
  for i = 0 to txq - 1 do
    start_tx t i
  done;
  t

(* TODO remove the + 1 *)
let wrap_ring index size = (index + 1) land (size - 1) [@@inline always]

let rx_batch t rxq_id =
  let { descriptors; rx_index; num_entries; pkt_bufs; mempool } as rxq =
    t.rxqs.(rxq_id) in
  let num_done =
    let rec loop i =
      let rxd = descriptors.(wrap_ring (rx_index + i - 1) num_entries) in
      if RXD.dd rxd then
        if not (RXD.eop rxd) then
          error "jumbo frames are not supported"
        else
          loop (i + 1)
      else
        i in
    loop 0 in
  let bufs =
    let empty_bufs =
      Memory.pkt_buf_alloc_batch mempool num_done in
    if Array.length empty_bufs <> num_done then
      error "could not allocate enough buffers";
    let receive offset =
      let index = wrap_ring (rx_index + offset - 1) num_entries in
      let buf = pkt_bufs.(index) in
      let rxd = descriptors.(index) in
      Memory.pkt_buf_resize buf (RXD.size rxd);
      let new_buf = empty_bufs.(offset) in
      RXD.reset descriptors.(index) new_buf;
      pkt_bufs.(index) <- new_buf;
      buf in
    Array.init num_done ~f:receive in
  if num_done > 0 then begin
    rxq.rx_index <- wrap_ring (rx_index + num_done - 1) num_entries;
    t.set_reg (IXGBE.RDT rxq_id) (Int32.of_int_exn rxq.rx_index)
  end;
  bufs

let tx_batch ?(clean_large = false) t txq_id bufs =
  let txq = t.txqs.(txq_id) in
  (* returns wether or not the descriptor at clean_index + offset can be cleaned *)
  let check offset =
    if txq.clean_index + offset land (txq.num_entries - 1) >= txq.tx_index then
      false
    else
      TXD.dd txq.descriptors.(wrap_ring (txq.clean_index + offset) txq.num_entries) in
  let clean_ahead offset =
    let cleanup_to =
      wrap_ring (txq.clean_index + offset - 1) txq.num_entries in
    let rec loop i =
      Memory.pkt_buf_free txq.pkt_bufs.(i);
      if i <> cleanup_to then
        loop (wrap_ring i txq.num_entries)
      else
        txq.clean_index <- wrap_ring cleanup_to txq.num_entries in
    loop txq.clean_index in
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
  let num_free_descriptors = (* TODO check this calculation *)
    (txq.clean_index - txq.tx_index) land (txq.num_entries - 1) in
  let n = Int.min num_free_descriptors (Array.length bufs) in
  for i = 0 to n - 1 do
    (* send packet *)
    TXD.reset txq.descriptors.(wrap_ring (txq.tx_index + i - 1) txq.num_entries) bufs.(i)
  done;
  txq.tx_index <- txq.tx_index + n;
  t.set_reg (IXGBE.TDT txq_id) (Int32.of_int_exn txq.tx_index);
  Array.sub bufs ~pos:n ~len:(Array.length bufs - n)

let tx_batch_busy_wait ?clean_large t txq_id bufs =
  while tx_batch ?clean_large t txq_id bufs <> [||] do
    ()
  done

let check_link t =
  let links_reg = t.get_reg IXGBE.LINKS in
  let speed =
    match Int32.(links_reg land IXGBE.LINKS.speed_82599) with
    | speed when speed = IXGBE.SPEED._10G -> `SPEED_10G
    | speed when speed = IXGBE.SPEED._1G -> `SPEED_1G
    | speed when speed = IXGBE.SPEED._100 -> `SPEED_100
    | _ -> `SPEED_UNKNOWN in
  let link_up = Int32.(links_reg land IXGBE.LINKS.up <> 0l) in
  (speed, link_up)
