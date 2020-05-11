open Ixy_memory
open Log

type hw =
  (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

type pci_config =
  { vendor : int
  ; device_id : int
  ; class_code : int
  ; subclass : int
  ; prog_if : int
  }

let vendor_intel = 0x8086

module type S = sig
  type t

  val map_resource : t -> hw

  val get_config : t -> pci_config

  val to_string : t -> string

  val allocate_dma :
    t -> ?require_contiguous:bool -> int -> Ixy_memory.dma_memory option

  val virt_to_phys : Cstruct.t -> Cstruct.uint64
end

module type Memory = sig
  include S

  val allocate_mempool : t -> ?pre_fill:Cstruct.t -> num_entries:int -> mempool

  val num_free_bufs : mempool -> int

  val pkt_buf_alloc_batch : mempool -> num_bufs:int -> pkt_buf array

  val pkt_buf_alloc : mempool -> pkt_buf option

  val pkt_buf_resize : pkt_buf -> size:int -> unit

  val pkt_buf_free : pkt_buf -> unit
end

module Make (S : S) = struct
  include S

  let allocate_mempool t ?pre_fill ~num_entries =
    let entry_size = 2048 in (* entry_size is fixed for now *)
    if huge_page_size mod entry_size <> 0 then
      error "entry size must be a divisor of huge page size (%d)" huge_page_size;
    let { virt; _ } =
      match S.allocate_dma t ~require_contiguous:false (num_entries * entry_size) with
      | None -> error "Could not allocate DMA memory"
      | Some mem -> mem in
    Cstruct.memset virt 0; (* might not be necessary *)
    let mempool =
      { entry_size;
        num_entries;
        free = num_entries;
        free_bufs = Array.make num_entries dummy
      } in
    let init_buf index =
      let data =
        Cstruct.sub virt (index * entry_size) entry_size in
      let size =
        match pre_fill with
        | Some init ->
          let len = Cstruct.len init in
          Cstruct.blit init 0 data 0 len;
          len
        | None -> entry_size in
      { phys = S.virt_to_phys data;
        mempool;
        size;
        data
      } in
    Array.iteri
      (fun i _ -> mempool.free_bufs.(i) <- init_buf i)
      mempool.free_bufs;
    mempool

  let num_free_bufs mempool = mempool.free

  let pkt_buf_alloc_batch mempool ~num_bufs =
    if num_bufs > mempool.num_entries then
      warn
        "can never allocate %d bufs in a mempool with %d bufs"
        num_bufs
        mempool.num_entries;
    let n = min num_bufs mempool.free in
    let alloc_start = mempool.free - n in
    let bufs = Array.sub mempool.free_bufs alloc_start n in
    mempool.free <- alloc_start;
    bufs

  let pkt_buf_alloc mempool =
    (* doing "pkt_buf_alloc_batch mempool ~num_bufs:1" has a bit more overhead *)
    if mempool.free > 0 then
      let index = mempool.free - 1 in
      mempool.free <- index;
      Some mempool.free_bufs.(index)
    else
      None

  let pkt_buf_free ({ mempool; _ } as buf) =
    mempool.free_bufs.(mempool.free) <- buf;
    mempool.free <- mempool.free + 1

  let pkt_buf_resize ({ mempool; _ } as buf) ~size =
    (* MTU is fixed at 1518 by default. *)
    let upper = min mempool.entry_size IXGBE.default_mtu in
    if size > 0 && size <= upper then
      buf.size <- size
    else
      error "0 < size <= %d is not fulfilled; size = %d" upper size
end
