open Core

open Log

module Memory = Memory

let max_rx_queue_entries = 4096
let max_tx_queue_entries = 4096

let num_rx_queue_entries = 512
let num_tx_queue_entries = 512

let tx_clean_batch = 32

type t = {
  hw : Pci.hw;
  pci_addr : string;
  rxq : int;
  txq : int;
  get_reg : int IXGBE.register -> int;
  set_reg : int IXGBE.register -> int -> unit;
  set_flags : int IXGBE.register -> int -> unit;
  clear_flags : int IXGBE.register -> int -> unit;
  wait_set : int IXGBE.register -> int -> unit;
  wait_clear : int IXGBE.register -> int -> unit
}

external uname : unit -> string = "caml_uname"

let check_system =
  let checked = ref false in
  fun () ->
    if not !checked then begin
      if Sys.os_type <> "Unix" || uname () <> "Linux" then
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
  t.set_reg IXGBE.EIMC 0x7FFFFFFF

let reset t =
  info "resetting device %s" t.pci_addr;
  t.set_reg IXGBE.CTRL IXGBE.CTRL_.ctrl_rst_mask;
  t.wait_clear IXGBE.CTRL IXGBE.CTRL_.ctrl_rst_mask;
  Caml.Unix.sleepf 0.01;
  info "reset done"

let init_link t =
  let autoc = t.get_reg IXGBE.AUTOC in
  t.set_reg IXGBE.AUTOC ((autoc land (lnot IXGBE.AUTOC_.lms_mask)) lor IXGBE.AUTOC_.lms_10G_serial);
  let autoc = t.get_reg IXGBE.AUTOC in
  t.set_reg IXGBE.AUTOC (autoc land (lnot IXGBE.AUTOC_._10G_pma_pmd_mask));
  t.set_flags IXGBE.AUTOC IXGBE.AUTOC_.an_restart

let init_rx t =
  t.clear_flags IXGBE.RXCTRL IXGBE.RXCTRL_.rxen;
  t.set_reg (IXGBE.RXPBSIZE 0) IXGBE.RXPBSIZE_._128KB;
  for i = 1 to 7 do
    t.set_reg (IXGBE.RXPBSIZE i) 0
  done;
  t.set_flags IXGBE.HLREG0 IXGBE.HLREG0_.rxcrcstrp;
  t.set_flags IXGBE.RDRXCTL IXGBE.RDRXCTL_.crcstrip;
  t.set_flags IXGBE.FCTRL IXGBE.FCTRL_.bam;
  for i = 0 to t.rxq - 1 do
    debug "initializing rxq %d" i;
    let srrctl = t.get_reg (IXGBE.SRRCTL i) in
    t.set_reg (IXGBE.SRRCTL i) ((srrctl land (lnot IXGBE.SRRCTL_.desctype_mask)) lor IXGBE.SRRCTL_.desctype_adv_onebuf);
    t.set_flags (IXGBE.SRRCTL i) IXGBE.SRRCTL_.drop_en;
    let ring_size_bytes = (8 * num_rx_queue_entries) in
    let mem = Memory.allocate_dma ~require_contiguous:true ring_size_bytes in
    for j = 0 to (2 * num_rx_queue_entries) - 1 do
      Memory.write8 mem.virt j 0xFF
    done;
    t.set_reg (IXGBE.RDBAL i) Int64.(to_int_exn @@ mem.phy land 0xFFFFFFFFL);
    t.set_reg (IXGBE.RDBAH i) Int64.(to_int_exn @@ mem.phy lsr 32); (* logical vs arithmetic here? *)
    t.set_reg (IXGBE.RDLEN i) ring_size_bytes;
    debug "rx ring %d phy addr: %#012LX" i mem.phy;
    t.set_reg (IXGBE.RDH i) 0;
    t.set_reg (IXGBE.RDT i) 0
  done

let init_tx t =
  t.set_flags IXGBE.HLREG0 (IXGBE.HLREG0_.txcrcen lor IXGBE.HLREG0_.txpaden)
(* FIXME memory allocation here *)

let create ~pci_addr ~rxq ~txq =
  check_system ();
  if Unix.getuid () <> 0 then
    warn "not running as root, this will probably fail";
  if rxq > IXGBE.max_queues then
    error "cannot configure %d rx queues (max: %d)" rxq IXGBE.max_queues;
  if txq > IXGBE.max_queues then
    error "cannot configure %d tx queues (max: %d)" txq IXGBE.max_queues;
  let hw = Pci.map_resource pci_addr in
  let t =
    { hw;
      pci_addr;
      rxq;
      txq;
      get_reg = IXGBE.get_reg hw;
      set_reg = IXGBE.set_reg hw;
      set_flags = IXGBE.set_flags hw;
      clear_flags = IXGBE.clear_flags hw;
      wait_set = IXGBE.wait_set hw;
      wait_clear = IXGBE.wait_clear hw
    } in
  (* allocate queues here *)
  disable_interrupts t;
  reset t;
  disable_interrupts t;
  info "initializing device %s" t.pci_addr;
  t.wait_set IXGBE.EEC IXGBE.EEC.ard;
  t.wait_set IXGBE.RDRXCTL IXGBE.RDRXCTL_.dmaidone;
  init_link t;
  (* read_stats *)
  init_rx t;
  init_tx t;
  t

let check_link t =
  let links_reg = t.get_reg IXGBE.LINKS in
  let speed =
    match (links_reg land IXGBE.LINKS_.speed_82599) with
    | speed when speed = IXGBE.SPEED_._10G -> `SPEED_10G
    | speed when speed = IXGBE.SPEED_._1G -> `SPEED_1G
    | speed when speed = IXGBE.SPEED_._100 -> `SPEED_100
    | _ -> `SPEED_UNKNOWN in
  let link_up = links_reg land IXGBE.LINKS_.up <> 0 in
  (speed, link_up)

let blink_mode t link blink =
  if blink then begin
    (*let speed, up = check_link t in
      if not up then begin
      let macc_reg = t.get_reg IXGBE.MACC in
      IXGBE.set_reg
        t.hw
        IXGBE.MACC
        (macc_reg lor (IXGBE.MACC_.flu lor IXGBE.MACC_.fsv lor IXGBE.MACC_.fs))
      end;*)
    let ledctl_reg = t.get_reg IXGBE.LEDCTL in
    t.set_reg IXGBE.LEDCTL ((ledctl_reg land (lnot @@ IXGBE.LED_.mode_mask link)) lor (IXGBE.LED_.blink link))
  end else begin
    let ledctl_reg = t.get_reg IXGBE.LEDCTL in
    ledctl_reg
    |> ( land ) (lnot @@ IXGBE.LED_.mode_mask link)
    |> ( lor ) (IXGBE.LED_.link_active lsl (IXGBE.LED_.mode_shift link))
    |> ( land ) (lnot @@ IXGBE.LED_.blink link)
    |> t.set_reg IXGBE.LEDCTL
    (*let macc_reg = t.get_reg IXGBE.MACC in
      t.set_reg IXGBE.MACC (macc_reg land (lnot @@ IXGBE.MACC_.flu lor IXGBE.MACC_.fsv lor IXGBE.MACC_.fs))*)
  end
