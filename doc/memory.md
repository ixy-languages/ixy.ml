# Memory

This document details the memory interface used by the ixy.ml driver and the Intel 82599 NIC to communicate with each other.
This document references the [Intel® 82599 10 GbE Controller Datasheet](https://www.intel.com/content/dam/www/public/us/en/documents/datasheets/82599-10-gbe-controller-datasheet.pdf). (TODO add references)
This document assumes a word size of 64 bit.

ixy refers to the [original C implementation by Paul Emmerich](https://github.com/emmericp/ixy) while ixy.ml refers to the [OCaml reimplementation by Fabian Bonk](https://github.com/ixy-languages/ixy.ml).

## ixy vs ixy.ml packet buffers

By default ixy allocates `(NUM_RX_QUEUE_ENTRIES + NUM_TX_QUEUE_ENTRIES) * 2048 = 16 MiB` per mempool.
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

The actual implementation is `struct pkt_buf` in [`ixy/src/memory.h`](https://github.com/emmericp/ixy/blob/master/src/memory.h).

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

### Read Format

The read format consists of two fields, each one word in size.
The driver writes the physical address of the packet buffer that is being described to the first word.
The second word contains a number of flags describing the buffer; the flags need to be reset when resetting a descriptor.
Resetting is done by writing `0` to the second word.
When the NIC receives a packet it writes the packet to the address specified in the first word.

### Write-Back Format

After receiving a packet the NIC updates the rx descriptor to notify the driver.
It uses the write-back format.
The relevant bit for the driver is the LSB of the second word, the Descriptor Done (DD) bit.
Once this bit is set the driver has written a packet to the buffer.
Additionally ixy and ixy.ml check if the End Of Packet (EOP) bit is set.
If this bit is not set the NIC had to split the packet up into multiple buffers which is currently not support by the driver.

Bits 32 through 47 of the second word of the write-back format indicate the received packet's length in bytes.

## Transmit Descriptors (tx descriptors)

(TODO add this section)

## Descriptor Ring

Descriptors for a queue are stored in a so-called descriptor ring.
A descriptor ring is a circular buffer with a head and a tail pointer.
The driver controls the tail pointer; the NIC controls the head pointer.
The descriptor ring is contiguous in memory.
It starts at a base address; head and tail are offsets from the base address.
Both ixy and ixy.ml only support rings whose descriptor capacity is a power of two: With this ring size, wrapping around the ring's end can be done without costly modulo operations (`next_index <- (current_index + 1) & (ring_size - 1)`, see `wrap_ring` in [`lib/ixy.ml`](../lib/ixy.ml)).
The tail pointer always points to the first invalid descriptor.
See 7.1.9.

## Receive flow

### Setup phase

During rx setup the driver initializes a number of rx queues.
Each queue maintains its own mempool as well as its own descriptor ring.
The descriptor ring gets filled with empty packet buffers.
Head and tail pointers are set to the same value; in our case 0.
The queues additionally need to maintain a mapping from descriptor ring index to packet buffer since the rx descriptor itself only contains a physical address of the packet buffer and this physical address gets overwritten by the NIC during the write-back phase.
Both ixy and ixy.ml use the `virtual_addresses` array within each queue.

### Active phase

After everything has been set up, control flow returns to the user program.
The user program periodically calls `rx_batch` to receive a batch of packets.

`rx_batch` walks the descriptor ring and checks every descriptor's DD bit.
If this bit is set, we know that the NIC has placed a packet in the buffer the descriptor points to.
Once we have reached a descriptor whose DD bit isn't set, we have reached the first empty descriptor, i.e. the head.

Now we can receive all packets between tail and head.
To prepare the packet for the user program we need to set its size.
The NIC stored the packet's size in the size field of the descriptor.
After fetching the size, the packet buffer's `size` field is updated.
Now the packet is done and its spot in the descriptor ring needs to be filled with a new empty packet buffer.

Now we just need to update the tail pointer to tell the hardware up to which point there are empty buffers in the ring.
We only update the tail pointer once to prevent unnecessary overhead from repeated PCIe transactions.

Note that ixy employs a slightly different rx strategy: ixy scans each descriptor and immediately receives it, if its DD bit is set, while ixy.ml walks the entire ring until it hits an empty descriptor.

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
d|   +--------+ <- base + tail             |
 |   |        |                            |
 |   | filled |                            |
 |   |        |                            |
 |   +--------+                            v
 |       |
 +-------+
```

* Descriptors between `head` and `tail` point to empty `pkt_buf`s waiting to be written to by the NIC.
* Descriptors between `tail` and `head` point to filled `pkt_buf`s that are ready to be received by the driver.

## Transmit flow

Like rx queues, tx queues maintain a descriptor ring.

### Setup phase

During tx setup the driver initializes a number of tx queues.
Head and tail pointers are also set to 0.
The tx setup is somewhat simpler than the rx setup, since there are no descriptors in the descriptor ring initially.
Descriptors will be added once the user program calls `tx_batch` with a number of packet buffers.

### Active phase

Once the user program calls `tx_batch` the driver performs two steps: cleanup and transmit.

#### Ring layout

```
 +-------+
 |       |
 |       v
 |   +--------+ <- base address            |
 |   |        |                            |
w|   | empty  |                            |
r|   |        |                            |
a|   +--------+ <- base + clean_index      |
p|   |        |                            |i
 |   | dirty  |                            |n
a|   |        |                            |c
r|   +--------+ <- base + head             |r
o|   |        |                            |e
u|   |        |                            |m
n|   | unsent |                            |e
d|   |        |                            |n
 |   |        |                            |t
 |   +--------+ <- base + tail             |
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

#### Cleanup

Before inserting the outgoing packets into the descriptor ring, the driver needs to clean previously sent descriptors.
To improve performance, cleanup has to be done in batches of 32 descriptors.

For performance reasons we can't actually read the head pointer; reading NIC registers requires a full PCIe transaction.
The buffers that may be ready to be cleaned are the ones between `clean_index` and the tail pointer; of these the ones that have their DD bit set are ready to be cleaned.
However, it is inefficient to check every descriptor's DD bit.
Therefore ixy checks the descriptor 32 ahead of `clean_index`; if this descriptor's DD bit is set, all the buffers that were skipped can also be cleaned.
After cleaning these buffers, `clean_index` can be incremented by 32 and the whole process can be repeated until a buffer, whose DD bit isn't set, is hit.

In addition to ixy's behavior, ixy.ml supports another cleanup strategy; this behavior can be switched on and off when calling `tx_batch`:
Optionally ixy.ml checks the descriptor 128 ahead of `clean_index`.
If this descriptor's DD bit is set, all 128 buffers can be cleaned at once and cleaning is done; remaining buffers will be cleaned upon the next call to `tx_batch`.
If the DD bit is not set the same procedure will be repeated for offsets of 64 and 32.
This favors large collections at once, thereby reducing the amount of memory reads and increasing the amount of descriptors cleaned in a single pass.
If `tx_batch` is called with `~clean_large:true` the second strategy will be chosen, otherwise ixy's behavior will be replicated.

#### Transmit

To transmit packets the driver just walks the descriptor ring, setting each descriptor to one of the packets that are to be transmitted, until it has sent all packets or hits a non-cleaned descriptor.
Once that's done the tail pointer register needs to be updated; ixy then returns the number of sent packets to the caller while ixy.ml returns the unsent packets themselves.
