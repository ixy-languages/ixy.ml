# Memory

This document details the memory interface used by the ixy.ml driver and the Intel 82599 NIC to communicate with each other.
This document references the [Intel® 82599 10 GbE Controller Datasheet](https://www.intel.com/content/dam/www/public/us/en/documents/datasheets/82599-10-gbe-controller-datasheet.pdf).
This document (as well as ixy.ml itself) assumes a word size of 64 bit.

ixy refers to the [original C implementation by Paul Emmerich](https://github.com/emmericp/ixy) while ixy.ml refers to the [OCaml reimplementation by Fabian Bonk](https://github.com/ixy-languages/ixy.ml).

## Thread-safety

ixy.ml is **not** thread-safe.
Invariants for each queue are only guaranteed to hold between calls to `rx_burst`/`tx_burst`.
Memory pools are not locked during operation; multiple threads must not allocate/free buffers in the same pool at the same time.

## ixy vs ixy.ml packet buffers

By default ixy allocates `4096 * 2 KiB = 16 MiB` for each rx queue's mempool.
This memory is not physically contiguous, as it doesn't fit into the 2 MiB huge pages used by ixy.
Theoretically each mempool should consume exactly 8 huge pages.
Back-to-back within this memory there are packet buffers:

```
 0     2047 2048  4095 4096 ... (byte offsets)
+----------+----------+-----
|   buf0   |   buf1   |     ...
+----------+----------+-----
```

### Buffer metadata

ixy stores buffer metadata in front of the packet data like so:
```
 0            7 8       15 16         19 20  23 24       63 64  2047 (byte offsets)
+--------------+----------+-------------+------+-----------+--------+
| buf_addr_phy | *mempool | mempool_idx | size | head_room | data[] |
+--------------+----------+-------------+------+-----------+--------+
 ^
 |
buf
```

The actual implementation is `struct pkt_buf` in [`ixy/src/memory.h`](https://github.com/emmericp/ixy/blob/bf4daff9adf1c5165a6d664678f3b7dd69b5640e/src/memory.h).

```c
struct pkt_buf {
    uintptr_t buf_addr_phy;
    struct mempool* mempool;
    uint32_t mempool_idx;
    uint32_t size;
    uint8_t head_room[SIZE_PKT_BUF_HEADROOM];
    uint8_t data[] __attribute__((aligned(64)));
};
```

* `buf_addr_phy` is the physical address of the beginning of the buffer (obtained via `virt_to_phys(buf)`).
* `*mempool` is a pointer to the mempool this packet buffer belongs to.
* `mempool_idx` is the index of the buffer within the mempool.
* `size` is the size of the packet data in bytes; this field is set after the NIC has set the packet's size in the rx descriptor or before the buffer is inserted into a tx ring.
* `head_room` are some empty bytes to align `data[]` on a 64 byte boundary.
* `data[]` is the location the NIC writes the packet's raw bytes to.

ixy stores the physical address of the beginning of the buffer, not the physical address of the `data` field to support virtio NICs.
Since ixy.ml only targets 82599 NICs we will store the address of the data field directly, i.e. `virt_to_phys(&buf->data)`.

Additionally since the NIC never accesses any field besides the `data` field we can have all other values live in the OCaml heap.
Since ixy.ml's hugepage only contains the data, ixy.ml effectively stores the same address as ixy.

Therefore ixy.ml's implementation of packet buffers looks like this:

```ocaml
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
```

`and` tells the compiler to introduce both type definitions at the same time since the definitions are mutually recursive: each `pkt_buf` points to the `mempool` it belongs to and each `mempool` maintains a stack (mutable index into an array) of empty buffers.

## Receive Descriptors (rx descriptors)

This chapter only details Advanced Receive Descriptors (7.1.6).

A rx descriptor is 16 bytes/2 words in size.
Its format changes depending on if the descriptor was written by the driver (read format, 7.1.6.1) or the NIC (write-back format, 7.1.6.2).

From `ixgbe_type.h` in the official `ixgbe` driver:
```c
/* Receive Descriptor - Advanced */
union ixgbe_adv_rx_desc {
  struct {
    __le64 pkt_addr; /* Packet buffer address */
    __le64 hdr_addr; /* Header buffer address */
  } read;
  struct {
    struct {
      union {
        __le32 data;
        struct {
          __le16 pkt_info; /* RSS, Pkt type */
          __le16 hdr_info; /* Splithdr, hdrlen */
        } hs_rss;
      } lo_dword;
      union {
        __le32 rss; /* RSS Hash */
        struct {
          __le16 ip_id; /* IP id */
          __le16 csum; /* Packet Checksum */
        } csum_ip;
      } hi_dword;
    } lower;
    struct {
      __le32 status_error; /* ext status/error */
      __le16 length; /* Packet length */
      __le16 vlan; /* VLAN tag */
    } upper;
  } wb;  /* writeback */
};
```

`ixgbe_adv_rx_desc.read` is the read format; `ixgbe_adv_rx_desc.wb` is the write-back format.

### Read Format

The read format consists of two fields, each one word in size.
The driver writes the physical address of the packet buffer that is being described to the first word.
The second word contains a number of flags describing the buffer; the flags need to be reset when resetting a descriptor.
Resetting is done by writing `0` to the second word.
When the NIC receives a packet it writes the packet to the address specified in the first word.

The read format accessors are generated from the following ppx_cstruct definition:

```ocaml
[%%cstruct
  type adv_rxd_read = {
    pkt_addr : uint64;
    hdr_addr : uint64
  } [@@little_endian]
]
```

### Write-Back Format

After receiving a packet the NIC updates the rx descriptor to notify the driver.
It uses the write-back format.
The relevant bit for the driver is the LSB of the second word, the Descriptor Done (`DD`) bit.
Once this bit is set the driver has written a packet to the buffer.
Additionally ixy and ixy.ml check if the End Of Packet (`EOP`) bit is set.

Bits 32 through 47 of the second word of the write-back format indicate the received packet's length in bytes.

The write-back format accessors are generated from the following ppx_cstruct definition:

```ocaml
[%%cstruct
  type adv_rxd_wb = {
    pkt_info : uint16;
    hdr_info : uint16;
    ip_id : uint16;
    csum : uint16;
    status_error : uint32;
    length : uint16;
    vlan : uint16
  } [@@little_endian]
]
```

## Transmit Descriptors (tx descriptors)

This chapter only details Advanced Receive Descriptors (7.2.3.2.4).

Like an rx descriptor, a tx descriptor is 16 bytes/2 words in size.
It, too, has read and write-back formats.

From `ixgbe_type.h` in the official `ixgbe` drivers:
```c
/* Transmit Descriptor - Advanced */
union ixgbe_adv_tx_desc {
  struct {
    __le64 buffer_addr; /* Address of descriptor's data buf */
    __le32 cmd_type_len;
    __le32 olinfo_status;
  } read;
  struct {
    __le64 rsvd; /* Reserved */
    __le32 nxtseq_seed;
    __le32 status;
  } wb;
};
```

Yet again `ixgbe_adv_tx_desc.read` is the read format; `ixgbe_adv_tx_desc.wb` is the write-back format.

### Read Format

The read format contains the physical address of a packet buffer that is to be transmitted.
Additionally there are a number of flags that need to be set.
Finally the payload's length needs to be specified.

The read format accessors are generated from the following ppx_cstruct definition:

```ocaml
[%%cstruct
  type adv_tx_read = {
    buffer_addr : uint64;
    cmd_type_len : uint32;
    olinfo_status : uint32
  } [@@little_endian]
]
```

### Write-back Format

The write-back format consists almost entirely of reserved bits (according to the datasheet).
The only actual flag is the `DD` flag.
Once this flag has been set, the NIC has transmitted the packet stored in the corresponding packet buffer.
The packet buffer is then ready to be cleaned.

The write-back format accessors are generated from the following ppx_cstruct definition:

```ocaml
[%%cstruct
  type adv_tx_wb = {
    rsvd : uint64;
    nxtseq_seed : uint32;
    status : uint32
  } [@@little_endian]
]
```

## Descriptor Ring

Descriptors for a queue are stored in a so-called descriptor ring.
A descriptor ring is a circular buffer with a head and a tail pointer.
The driver controls the tail pointer; the NIC controls the head pointer.
The descriptor ring is contiguous in memory.
It starts at a base address; head and tail are offsets from the base address.
Both ixy and ixy.ml only support rings whose descriptor capacity is a power of two: With this ring size, wrapping around the ring's end can be done without costly modulo operations (`next_index <- (current_index + 1) & (ring_size - 1)`, see `wrap_rx` and `wrap_tx` in [`lib/ixy.ml`](../lib/ixy.ml)).
The tail pointer always points to the first invalid descriptor.
See 7.1.9.

## Receive flow

### Ring layout

```
 +-------+
 |       |
 |       v
 |   +--------+ <- base address            |
 |   |        |                            |
 |   |        |                            |
 |   |        |                            |
w|   | filled |                            |
r|   |        |                            |i
a|   |        |                            |n
p|   |        |                            |c
 |   +--------+ <- base + head             |r
a|   |        |                            |e
r|   |        |                            |m
o|   | empty  |                            |e
u|   |        |                            |n
n|   |        |                            |t
d|   +--------+ <- base + tail (rx_index)  |
 |   |        |                            |
 |   | filled |                            |
 |   |        |                            |
 |   +--------+                            v
 |       |
 +-------+
```

* Descriptors between `head` and `tail` point to empty `pkt_buf`s waiting to be written to by the NIC.
* Descriptors between `tail` and `head` point to filled `pkt_buf`s that are ready to be received by the driver.

### Setup phase

During rx setup the driver initializes a number of rx queues.
Each queue maintains its own mempool as well as its own descriptor ring.
The descriptor ring is filled with empty packet buffers.
Head and tail pointers are set to the same value; in our case `0`.
The queues additionally need to maintain a mapping from descriptor ring index to packet buffer since the rx descriptor itself only contains the physical address of the packet buffer and this physical address gets overwritten by the NIC during the write-back phase.
ixy uses the `virtual_addresses` array in its queue while ixy.ml calls this array `pkt_bufs`.

`pkt_bufs.(i)` contains the `pkt_buf` described by the rx descriptor in `descriptors.(i)`.

### Active phase

After everything has been set up, control flow returns to the user program.
The user program periodically calls `rx_batch` to receive a batch of packets.

`rx_batch` walks the descriptor ring and checks every descriptor's `DD` bit.
If this bit is set, we know that the NIC has placed a packet in the buffer the descriptor points to.
Once we have reached a descriptor whose `DD` bit isn't set, we have reached the first empty descriptor, i.e. the head.

Now we can receive all packets between tail and head.
To prepare the packet for the user program we need to set its size.
The NIC stored the packet's size in the size field of the descriptor.
After fetching the size, the packet buffer's `size` field is updated.
Now the packet is done and its spot in the descriptor ring needs to be filled with a new empty packet buffer.

Now we just need to update the tail pointer to tell the hardware up to which point there are empty buffers in the ring.
We only update the tail pointer once to prevent unnecessary overhead from repeated PCIe transactions.

Note that ixy employs a slightly different rx strategy: ixy scans each descriptor and immediately receives its corresponding packet, if its `DD` bit is set, while ixy.ml walks the entire ring until it hits an empty descriptor and then receives all previous descriptors' packets at once.

Both ixy and ixy.ml additionally check a descriptors `EOP` (end of packet) bit before receiving.
If this bit is not set, the packet did not fit into the 2 KiB packet buffer and had to be split up.
Currently neither ixy nor ixy.ml support jumbo frames.
This check is not strictly necessary, since the 82599's default `MAXFRS` (max frame size) is 1518 (Ethernet default) and `JUMBOEN` (enable jumbo frames) is disabled by default.

## Transmit flow

Like rx queues, tx queues maintain a descriptor ring.

### Ring layout

```
 +-------+
 |       |
 |       v
 |   +--------+ <- base address            |
 |   |        |                            |
 |   | empty  |                            |
 |   |        |                            |
w|   +--------+ <- base + clean_index      |
r|   |        |                            |i
a|   | dirty  |                            |n
p|   |        |                            |c
 |   +--------+ <- base + head             |r
a|   |        |                            |e
r|   |        |                            |m
o|   | unsent |                            |e
u|   |        |                            |n
n|   |        |                            |t
d|   +--------+ <- base + tail (tx_index)  |
 |   |        |                            |
 |   | empty  |                            |
 |   |        |                            |
 |   +--------+                            v
 |       |
 +-------+
```

* Descriptors between `clean_index` and `head` are previously inserted packets that have been sent by the NIC.
* Descriptors between `head` and `tail` point to previously inserted packets that haven't been sent by the NIC.
* Descriptors between `tail` and `clean_index` are cleaned and ready-to-use.

### Setup phase

During tx setup the driver initializes a number of tx queues.
Head and tail pointers are also set to `0`.
The tx setup is somewhat simpler than the rx setup, since there are no descriptors in the descriptor ring initially.
Descriptors will be added once the user program calls `tx_batch` with a number of packet buffers.

### Active phase

Once the user program calls `tx_batch` the driver performs two steps: cleanup and transmit.

#### Cleanup

Before inserting the outgoing packets into the descriptor ring, the driver needs to clean previously sent descriptors.
To improve performance, cleanup is done in batches of 32 descriptors.

For performance reasons we can't actually read the head pointer; reading NIC registers requires a full PCIe transaction.
The buffers that may be ready to be cleaned are the ones between `clean_index` and the tail pointer; of these the ones that have their `DD` bit set are ready to be cleaned.
However, it is inefficient to check every descriptor's `DD` bit.
Therefore ixy checks the descriptor 32 ahead of `clean_index`; if this descriptor's `DD` bit is set, all the buffers that were skipped can also be cleaned.
After cleaning these buffers, `clean_index` can be incremented by 32 and the whole process can be repeated until a buffer, whose `DD` bit isn't set, is hit.

#### Transmit

To transmit packets the driver just walks the descriptor ring, setting each descriptor to one of the packets that are to be transmitted, until it has sent all packets or hits a non-cleaned descriptor.
Once that's done the tail pointer register needs to be updated; ixy then returns the number of sent packets to the caller while ixy.ml returns the unsent packets themselves.

### Invariants

`tx_index` points to the buffer into which the next transmitted packet will be inserted.
`clean_index` points to the next buffer to be cleaned.
Buffers in `[tx_index, clean_index)` are already cleaned and may be used.
Buffers in `[clean_index, tx_index)` must be checked and possibly cleaned.

`tx_index` is always "ahead" of `clean_index`.
Only before the first packet has been transmitted will `tx_index` and `clean_index` be equal, though no cleaning will be done until at least 32 packets have been transmitted.

After at least `num_tx_queue_entries` packets have been sent, `pkt_bufs.(i)` contains the `pkt_buf` described by the tx descriptor in `descriptors.(i)`.
Before that `pkt_bufs` will be filled with dummy buffers (that **must not be freed**) and `descriptors` will be filled with descriptors pointing to `0xffffffffffffffff`.
`0xffffffffffffffff` is used instead of `0` to cause rogue writes to trigger a DMA error instead of actually writing to physical memory (see [Snabb's implementation](https://github.com/snabbco/snabb/blob/771b55c829f42a1a788002c2924c6d7047cd1568/src/apps/intel/intel10g.lua#L169)).
