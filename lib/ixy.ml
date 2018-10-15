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
  descriptors : Memory.virt;
  mempool : Memory.mempool;
  num_entries : int;
  mutable rx_index : int; (* descriptor ring tail pointer  *)
  virtual_addresses : Memory.pkt_buf array;
}

type txq = {
  descriptors : Memory.virt;
  num_entries : int;
  mutable clean_index : int; (* first unclean descriptor *)
  mutable tx_index : int; (* descriptor ring tail pointer *)
  virtual_addresses : Memory.pkt_buf option array; (* TODO might be unboxed *)
}

type t = {
  hw : PCI.hw;
  pci_addr : string;
  num_rxq : int;
  mutable rxqs : rxq array; (* TODO mutability needed? *)
  num_txq : int;
  mutable txqs : txq array;
  get_reg : int IXGBE.register -> int;
  set_reg : int IXGBE.register -> int -> unit;
  set_flags : int IXGBE.register -> int -> unit;
  clear_flags : int IXGBE.register -> int -> unit;
  wait_set : int IXGBE.register -> int -> unit;
  wait_clear : int IXGBE.register -> int -> unit
}

let check_system =
  let checked = ref false in
  fun () ->
    if not !checked then begin
      if Sys.os_type <> "Unix" || (Uname.uname ()).sysname <> "Linux" then
        error "ixy.ml only works on Linux"
      else if Sys.word_size <> 64 then
        error "ixy.ml only works on 64 bit systems"
      else if Sys.big_endian then
        error "ixy.ml only works on little endian systems"
      else
        checked := true
    end

let disable_interrupts t =
  info "disabling interrupts";
  t.set_reg IXGBE.EIMC IXGBE.EIMC.interrupt_disable

let reset t =
  info "resetting device %s" t.pci_addr;
  t.set_reg IXGBE.CTRL IXGBE.CTRL.ctrl_rst_mask;
  t.wait_clear IXGBE.CTRL IXGBE.CTRL.ctrl_rst_mask;
  Caml.Unix.sleepf 0.01;
  info "reset done"

let init_link t =
  let autoc = t.get_reg IXGBE.AUTOC in
  t.set_reg
    IXGBE.AUTOC
    ((autoc land (lnot IXGBE.AUTOC.lms_mask)) lor IXGBE.AUTOC.lms_10G_serial);
  let autoc = t.get_reg IXGBE.AUTOC in
  t.set_reg
    IXGBE.AUTOC
    (autoc land (lnot IXGBE.AUTOC._10G_pma_pmd_mask));
  t.set_flags IXGBE.AUTOC IXGBE.AUTOC.an_restart

let init_rx t =
  (* disable RX while configuring *)
  t.clear_flags IXGBE.RXCTRL IXGBE.RXCTRL.rxen;
  if t.num_rxq > 0 then begin
    (* 128KB packet buffers *)
    t.set_reg (IXGBE.RXPBSIZE 0) IXGBE.RXPBSIZE._128KB;
    for i = 1 to 7 do
      t.set_reg (IXGBE.RXPBSIZE i) 0
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
              ((srrctl land (lnot IXGBE.SRRCTL.desctype_mask)) lor IXGBE.SRRCTL.desctype_adv_onebuf);
            (* drop packets if no rx descriptors available *)
            t.set_flags (IXGBE.SRRCTL i) IXGBE.SRRCTL.drop_en;
            (* setup descriptor ring *)
            let ring_size_bytes =
              rx_descriptor_bytes * num_rx_queue_entries in
            let descriptor_ring =
              Memory.allocate_dma ~require_contiguous:true ring_size_bytes in
            (* set all descriptor bytes to 0xFF to prevent memory problems *)
            for j = 0 to ring_size_bytes - 1 do
              Memory.write8 descriptor_ring.virt j 0xFF
            done;
            (* set base address *)
            t.set_reg (IXGBE.RDBAL i) Int64.(to_int_exn @@ descriptor_ring.phys land 0xFFFFFFFFL);
            t.set_reg (IXGBE.RDBAH i) Int64.(to_int_exn @@ descriptor_ring.phys lsr 32);
            (* set ring length *)
            t.set_reg (IXGBE.RDLEN i) ring_size_bytes;
            debug "rx ring %d phy addr: %#018Lx" i descriptor_ring.phys;
            (* ring head = ring tail = 0
             * -> ring is empty
             * -> NIC won't write packets until we start the queue *)
            t.set_reg (IXGBE.RDH i) 0;
            t.set_reg (IXGBE.RDT i) 0;
            let mempool_size = num_rx_queue_entries + num_tx_queue_entries in
            let mempool =
              Memory.allocate_mempool
                ~entry_size:2048
                ~num_entries:(Int.max mempool_size 4096) in
            let virtual_addresses =
              Memory.pkt_buf_alloc_batch mempool ~num_bufs:num_rx_queue_entries in
            { descriptors = descriptor_ring.virt;
              mempool;
              num_entries = num_rx_queue_entries;
              rx_index = 0;
              virtual_addresses
            }
          ) in
    (* disable no snoop *)
    t.set_flags IXGBE.CTRL_EXT IXGBE.CTRL_EXT.ns_dis;
    (* set magic bits *)
    for i = 0 to t.num_rxq - 1 do
      t.clear_flags (IXGBE.DCA_RXCTRL i) (1 lsl 12)
    done;
    t.set_flags IXGBE.RXCTRL IXGBE.RXCTRL.rxen; (* warum hier? *)
    t.rxqs <- rxqs
  end

let reset_rx_desc base n pkt_buf =
  let offset = n * rx_descriptor_bytes in
  Memory.write64 base offset (Memory.pkt_buf_get_phys pkt_buf);
  Memory.write64 base (offset + 8) 0L

let start_rx t i =
  info "starting rxq %d" i;
  let rxq = t.rxqs.(i) in
  let rxd = rxq.descriptors in
  if rxq.num_entries land (rxq.num_entries - 1) <> 0 then
    error "number of rx queue entries must be a power of 2";
  (* reset all descriptors *)
  Array.iteri rxq.virtual_addresses ~f:(reset_rx_desc rxd);
  t.set_flags (IXGBE.RXDCTL i) IXGBE.RXDCTL.enable;
  t.wait_set (IXGBE.RXDCTL i) IXGBE.RXDCTL.enable;
  t.set_reg (IXGBE.RDH i) 0;
  t.set_reg (IXGBE.RDT i) (rxq.num_entries - 1)

let init_tx t =
  if t.num_txq > 0 then begin
    (* enable crc offload and small packet padding *)
    t.set_flags IXGBE.HLREG0 (IXGBE.HLREG0.txcrcen lor IXGBE.HLREG0.txpaden);
    t.set_reg (IXGBE.TXPBSIZE 0) IXGBE.TXPBSIZE._40KB;
    for i = 1 to 7 do
      t.set_reg (IXGBE.TXPBSIZE i) 0
    done;
    t.set_reg IXGBE.DTXMXSZRQ 0xFFFF;
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
            for j = 0 to ring_size_bytes - 1 do
              Memory.write8 descriptor_ring.virt j 0xFF
            done;
            (* set base address *)
            t.set_reg (IXGBE.TDBAL i) Int64.(to_int_exn @@ descriptor_ring.phys land 0xFFFFFFFFL);
            t.set_reg (IXGBE.TDBAH i) Int64.(to_int_exn @@ descriptor_ring.phys lsr 32);
            (* set ring length *)
            t.set_reg (IXGBE.TDLEN i) ring_size_bytes;
            debug "tx ring %d phy addr: %#018Lx" i descriptor_ring.phys;
            let txdctl =
              t.get_reg (IXGBE.TXDCTL i) in
            let txdctl =
              txdctl land ((lnot 0x3F) lor (0x3F lsl 8) lor (0x3F lsl 16)) in
            let txdctl =
              txdctl lor (36 lor (8 lsl 8) lor (4 lsl 16)) in
            t.set_reg (IXGBE.TXDCTL i) txdctl;
            let virtual_addresses = (* maybe fill with null buffers to avoid indirections *)
              Array.init num_tx_queue_entries ~f:(fun _ -> None) in
            { descriptors = descriptor_ring.virt;
              num_entries = num_tx_queue_entries;
              clean_index = 0;
              tx_index = 0;
              virtual_addresses;
            }) in
    t.set_reg IXGBE.DMATXCTL IXGBE.DMATXCTL.te;
    t.txqs <- txqs
  end

let start_tx t i =
  info "starting txq %d" i;
  let txq = t.txqs.(i) in
  if txq.num_entries land (txq.num_entries - 1) <> 0 then
    error "number of tx queue entries must be a power of 2";
  t.set_reg (IXGBE.TDH i) 0;
  t.set_reg (IXGBE.TDT i) 0;
  t.set_flags (IXGBE.TXDCTL i) IXGBE.TXDCTL.enable;
  t.wait_set (IXGBE.TXDCTL i) IXGBE.TXDCTL.enable

let create ~pci_addr ~rxq ~txq =
  check_system ();
  if Unix.getuid () <> 0 then
    warn "not running as root, this will probably fail";
  if rxq > IXGBE.max_queues then
    error "cannot configure %d rx queues (max: %d)" rxq IXGBE.max_queues;
  if txq > IXGBE.max_queues then
    error "cannot configure %d tx queues (max: %d)" txq IXGBE.max_queues;
  let PCI.{ vendor; device_id; class_code; subclass; prog_if } =
    PCI.get_config pci_addr in
  begin match class_code, subclass, prog_if, vendor with
  | 0x2, 0x0, 0x0, v when v = PCI.vendor_intel -> ()
  | 0x1, 0x0, 0x0, v when v = PCI.vendor_intel -> (* TODO make these errors *)
    warn "device %s is configured as SCSI storage device in EEPROM" pci_addr
  | 0x2, 0x0, _, v when v <> PCI.vendor_intel ->
    warn "device %s is a non-Intel NIC (vendor: %#x)" pci_addr vendor
  | 0x2, _, _, _ ->
    warn "device %s is not an Ethernet NIC (subclass: %#x)" pci_addr subclass
  | _ ->
    warn "device %s is not a NIC (class: %#x)" pci_addr class_code
  end;
  info "device %s has device id %#x" pci_addr device_id;
  let hw =
    PCI.map_resource pci_addr in
  let t =
    { hw;
      pci_addr;
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

let wrap_ring index size = (index + 1) land (size - 1) [@@inline always]

let rx_batch t rxq_id =
  let rxq = t.rxqs.(rxq_id) in
  let rec loop rx_index last_rx_index acc =
    let desc_ptr =
      Memory.offset_ptr rxq.descriptors (rx_index * rx_descriptor_bytes) in
    let status =
      Memory.read32 desc_ptr 8 in (* TODO check this offset *)
    if status land IXGBE.ADV_RXD.stat_dd <> 0 then begin
      if status land IXGBE.ADV_RXD.stat_eop = 0 then
        error
          "multi-segment packets are not supported - increase buffer size or decrease MTU";
      let buf = rxq.virtual_addresses.(rx_index) in
      let size =
        Memory.read16 desc_ptr 12 in (* TODO check this offset *)
      Memory.pkt_buf_resize buf size;
      let new_buf =
        match Memory.pkt_buf_alloc rxq.mempool with
        | None -> error "failed to allocate new mbuf"
        | Some buf -> buf in
      rxq.virtual_addresses.(rx_index) <- new_buf;
      reset_rx_desc desc_ptr rx_index new_buf;
      debug "received packet on device %s queue %d" t.pci_addr rxq_id;
      loop (wrap_ring rx_index rxq.num_entries) rx_index (buf :: acc)
    end else begin
      if rx_index <> last_rx_index then begin
        t.set_reg (IXGBE.RDT rxq_id) last_rx_index;
        rxq.rx_index <- rx_index
      end;
      acc
    end in
  loop rxq.rx_index rxq.rx_index []
  |> List.rev

let tx_batch ?(clean_large = false) t txq_id bufs =
  let txq = t.txqs.(txq_id) in
  (* returns wether or not the descriptor at clean_index + offset can be cleaned *)
  let check offset =
    if txq.clean_index + offset land (txq.num_entries - 1) >= txq.tx_index then
      false
    else
    let desc_ptr =
      Memory.offset_ptr txq.descriptors ((txq.clean_index + offset) * tx_descriptor_bytes) in
    let status =
      Memory.read32 desc_ptr 12 in (* TODO check this offset *)
    status land IXGBE.ADV_TXD.stat_dd <> 0 in
  let clean_until offset =
    let cleanup_to =
      txq.clean_index + offset - 1 in
    let rec loop i =
      let buf =
        match txq.virtual_addresses.(i) with
        | None -> error "no buffer to free at index %d" i
        | Some buf -> buf in
      Memory.pkt_buf_free buf;
      if i <> cleanup_to then
        loop (wrap_ring i txq.num_entries)
      else
        txq.clean_index <- wrap_ring cleanup_to txq.num_entries in
    loop txq.clean_index in
  if clean_large then begin
    if check 128 then (* possibly quicker batching *)
      clean_until 128
    else if check 64 then
      clean_until 64
    else if check 32 then
      clean_until 32
  end else begin
    while check tx_clean_batch do (* default ixy behavior *)
      clean_until tx_clean_batch
    done
  end;
  let reset_tx_desc base n pkt_buf =
    let offset = n * rx_descriptor_bytes in
    Memory.write64 base offset (Memory.pkt_buf_get_phys pkt_buf);
    let len = (* TODO fix this crappy cast *)
      Bytes.length (Obj.magic (Memory.pkt_buf_get_data pkt_buf) : Core.Bytes.t) in
    Memory.write32
      base
      (offset + 8)
      IXGBE.ADV_TXD.(dcmd_eop lor dcmd_rs lor dcmd_ifcs lor dcmd_dext lor dtyp_data lor len);
    Memory.write32
      base
      (offset + 12)
      (len lsl IXGBE.ADV_TXD.paylen_shift) in
  let rec loop bufs =
    let next_index = wrap_ring txq.tx_index txq.num_entries in
    if next_index = txq.clean_index then
      bufs
    else
    match bufs with
    | hd :: tl ->
      txq.virtual_addresses.(txq.tx_index) <- Some hd;
      reset_tx_desc txq.descriptors txq.tx_index hd;
      txq.tx_index <- wrap_ring txq.tx_index txq.num_entries;
      loop tl
    | [] -> [] in
  loop bufs

let check_link t =
  let links_reg = t.get_reg IXGBE.LINKS in
  let speed =
    match (links_reg land IXGBE.LINKS.speed_82599) with
    | speed when speed = IXGBE.SPEED._10G -> `SPEED_10G
    | speed when speed = IXGBE.SPEED._1G -> `SPEED_1G
    | speed when speed = IXGBE.SPEED._100 -> `SPEED_100
    | _ -> `SPEED_UNKNOWN in
  let link_up = links_reg land IXGBE.LINKS.up <> 0 in
  (speed, link_up)

let blink_mode t link blink =
  if blink then begin
    (*let speed, up = check_link t in
      if not up then begin
      let macc_reg = t.get_reg IXGBE.MACC in
      IXGBE.set_reg
        t.hw
        IXGBE.MACC
        (macc_reg lor (IXGBE.MACC.flu lor IXGBE.MACC.fsv lor IXGBE.MACC.fs))
      end;*)
    let ledctl_reg = t.get_reg IXGBE.LEDCTL in
    t.set_reg IXGBE.LEDCTL ((ledctl_reg land (lnot @@ IXGBE.LEDCTL.mode_mask link)) lor (IXGBE.LEDCTL.blink link))
  end else begin
    let ledctl_reg = t.get_reg IXGBE.LEDCTL in
    ledctl_reg
    |> ( land ) (lnot @@ IXGBE.LEDCTL.mode_mask link)
    |> ( lor ) (IXGBE.LEDCTL.link_active lsl (IXGBE.LEDCTL.mode_shift link))
    |> ( land ) (lnot @@ IXGBE.LEDCTL.blink link)
    |> t.set_reg IXGBE.LEDCTL
    (*let macc_reg = t.get_reg IXGBE.MACC in
      t.set_reg IXGBE.MACC (macc_reg land (lnot @@ IXGBE.MACC.flu lor IXGBE.MACC.fsv lor IXGBE.MACC.fs))*)
  end
