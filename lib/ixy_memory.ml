let huge_page_bits = 21
let huge_page_size = 1 lsl huge_page_bits

external ixy_int64_of_addr :
  Cstruct.buffer -> int -> Cstruct.uint64 = "ixy_int64_of_addr"

let int64_of_addr Cstruct.{ buffer; off; _ } =
  ixy_int64_of_addr buffer off

type dma_memory = {
  virt : Cstruct.t;
  physical : Cstruct.uint64
}

type mempool = {
  entry_size : int;
  num_entries : int;
  mutable free : int;
  free_bufs : pkt_buf array;
}

and pkt_buf = {
  phys : Cstruct.uint64;
  mempool : mempool;
  mutable size : int;
  data : Cstruct.t
}

let dummy =
  let dummy_pool =
    { entry_size = 0;
      num_entries = 0;
      free = 0;
      free_bufs = [||] (* ensure out of bounds write when freed *)
    } in
  { phys = 0xFFFF_FFFF_FFFF_FFFFL; (* ensure DMA error on access *)
    mempool = dummy_pool;
    size = 0;
    data = Cstruct.empty
  }
