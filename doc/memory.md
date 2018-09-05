# Memory

This document details the memory interface used by the ixy.ml driver and the Intel 82599 NIC to communicate with each other.
This document references the [Intel® 82599 10 GbE Controller Datasheet](https://www.intel.com/content/dam/www/public/us/en/documents/datasheets/82599-10-gbe-controller-datasheet.pdf). (TODO add references)
This document assumes a word size of 64 bit.

ixy refers to the [original C implementation by Paul Emmerich](https://github.com/emmericp/ixy) while ixy.ml refers to the [OCaml reimplementation by Fabian Bonk](https://github.com/ixy-languages/ixy.ml).

## OCaml String Format

ixy.ml represents packet payloads as OCaml strings (actually `bytes` to allow for in-place mutation).
See [`doc/ocaml_internals.md`](./ocaml_internals.md) for more details on OCaml memory representation.

Consider the following OCaml code:
```ocaml
let my_string = "hello"
```

`my_string` is represented as a pointer to a heap block containing the five characters of the string in their standard ASCII representation, followed by three padding bytes, of which the last byte indicates the number of padding bytes preceding it, and preceded by a header block containing metadata such as the string's length in machine words (`1` in this case).

```
|<-1 word->|<-----------------------------1 word----------------------------->|
|          |                                                                  |
|-64     -1|0     7 8    15 16   23 24   31 32   39 40    47 48    55 56    63| (bit offsets)
+----------+-------+-------+-------+-------+-------+--------+--------+--------+
|  header  |  'h'  |  'e'  |  'l'  |  'l'  |  'o'  |  0x00  |  0x00  |  0x02  |
+----------+-------+-------+-------+-------+-------+--------+--------+--------+
            ^                                      |<--------padding--------->|
            |
        my_string
```

If we want the NIC to write directly to such a string we need to modify the buffer the descriptor points to as well as offset the buffer address.

### `string` vs `bytes`

Since version 4.02.0 OCaml differentiates between two types of strings: `string` and `bytes`.
Values of type `bytes` are mutable while values of type `string` are immutable. Previously there was no `bytes` type and all values of type `string` were mutable.

## ixy vs ixy.ml packet buffers

By default ixy allocates `(NUM_RX_QUEUE_ENTRIES + NUM_TX_QUEUE_ENTRIES) * 2048 = 16 MiB` per mempool.
This memory is not physically contiguous, as it doesn't fit into the 2 MiB huge pages used by ixy, though the virtual addresses are contiguous. (TODO check this)
Theoretically each mempool should consume exactly 8 huge pages.
Back-to-back within this memory there are packet buffers:

```
 0     2047 2048  4095 4096 ... (byte offsets)
+----------+----------+-----
|   buf0   |   buf1   |     ...
+----------+----------+-----
```

ixy.ml requires each of these buffers to be a valid OCaml string.
There is no easy way to access arbitrary memory as `bytes` in OCaml; usually strings are copied to the OCaml heap using `caml_copy_string()`.
Since we can't afford to copy each packet buffer to the OCaml heap we need to trick OCaml into using the packet buffer directly.
Therefore we need to construct our own header and padding.

### OCaml block header

An OCaml block is always preceded by a header adhering to the following format:
```
|<---------1 word--------->|
|0         53 54   55 56 63| (bit offsets)
+------------+-------+-----+
| block size | color | tag |
+------------+-------+-----+
```

* `block size` is the size of the block in machine words. Every string is at least one word in size; even the empty string contains a padding word.
* `color` is set by the garbage collector and stores reachability information.
This is irrelevant for our purposes since the GC never visits packet buffers as they are located outside the OCaml heap.
* `tag` tells the garbage collector wether the block contains other blocks that may need to be scanned.
This is also irrelevant for our purposes, though we simply set it to `String_tag` just in case a runtime type check is done (may be done by the bytecode interpreter).
If the `tag` is greater than or equal to `No_scan_tag` (251) the garbage collector will not scan the block.
The `String_tag` (252) is greater than the `No_scan_tag` since strings don't contain OCaml blocks.

### OCaml string padding

OCaml strings are always padded to the next word length.
The padding consists of `n` null bytes and a last byte of value `n`.
On a 64 bit machine the following are all possible string paddings, depending on the length of the string modulo 8:
```
   ------+------+------+------+------+------+------+------+------+
... data | 0x00 | 0x00 | 0x00 | 0x00 | 0x00 | 0x00 | 0x00 | 0x07 | len(data) % 8 = 0
   ------+------+------+------+------+------+------+------+------+

   -------------+------+------+------+------+------+------+------+
... data        | 0x00 | 0x00 | 0x00 | 0x00 | 0x00 | 0x00 | 0x06 | len(data) % 8 = 1
   -------------+------+------+------+------+------+------+------+

   --------------------+------+------+------+------+------+------+
... data               | 0x00 | 0x00 | 0x00 | 0x00 | 0x00 | 0x05 | len(data) % 8 = 2
   --------------------+------+------+------+------+------+------+

   ---------------------------+------+------+------+------+------+
... data                      | 0x00 | 0x00 | 0x00 | 0x00 | 0x04 | len(data) % 8 = 3
   ---------------------------+------+------+------+------+------+

   ----------------------------------+------+------+------+------+
... data                             | 0x00 | 0x00 | 0x00 | 0x03 | len(data) % 8 = 4
   ----------------------------------+------+------+------+------+

   -----------------------------------------+------+------+------+
... data                                    | 0x00 | 0x00 | 0x02 | len(data) % 8 = 5
   -----------------------------------------+------+------+------+

   ------------------------------------------------+------+------+
... data                                           | 0x00 | 0x01 | len(data) % 8 = 6
   ------------------------------------------------+------+------+

   -------------------------------------------------------+------+
... data                                                  | 0x00 | len(data) % 8 = 7
   -------------------------------------------------------+------+
```

This format ensures that all OCaml strings have at least one trailing null byte.
OCaml does not rely on the trailing null byte when computing a string's length since the number of words the string occupies is stored in the header.
Therefore an OCaml string's length is computed like so:
```
len(string) = (header.size * 8) - final_padding_byte - 1
```

OCaml strings may contain null bytes, therefore they cannot always be passed to C functions such as `strcmp()` or `strcpy()`.

See also [the string section in Real World OCaml](https://dev.realworldocaml.org/runtime-memory-layout.html#string-values).

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

* `buf_addr_phy` is the physical address of the beginning of the buffer (obtained via `virt_to_phys(buf)`)
* `*mempool` is a pointer to the mempool this packet buffer belongs to
* `mempool_idx` is the index of the buffer within the mempool
* `size` is the size of the packet data in bytes; this field is set once the NIC has set the packet's size in the rx descriptor
* `head_room` are some empty bytes to align `data[]` on a 64 byte boundary
* `data[]` is the location the NIC writes the packet's raw bytes to

ixy stores the physical address of the beginning of the buffer, not the physical address of the `data` field to support virtio NICs.
Since ixy.ml only targets 82599 NICs we will store the address of the data field directly, i.e. `virt_to_phys(&buf->data)`.

Additionally since the NIC never accesses any field besides the `data` field we can have all other values live in the OCaml heap.
Unfortunately we still need to waste the first 64 bytes of each buffer since we need room for the OCaml string header.

Therefore ixy.ml buffers look like this:
```
 -64     -9 -8    -1 0                  1983 (byte offsets)
+----------+--------+-------------+---------+
| headroom | header | packet data | padding |
+----------+--------+-------------+---------+
                     ^
                     |
                    buf
```
Since there is always at least one padding byte the maximum packet data length for ixy.ml is 1983 bytes.

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

## Descriptor Ring

Descriptors for a queue are stored in a so-called descriptor ring.
A descriptor ring is a circular buffer with a head and a tail pointer.
The driver controls the tail pointer; the NIC controls the head pointer.
The descriptor ring is contiguous in memory.
It starts at a base address; head and tail are offsets from the base address.
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
To prepare the packet for the user program we need to set its size.
The NIC stored the packet's size in the size field of the descriptor.
After fetching the size the packet buffer needs to be resized by modifying the OCaml string header's size field and writing the appropriate padding.
Now the packet is done and its spot in the descriptor ring needs to be filled by a new empty packet buffer.

Once we have reached a descriptor whose DD bit isn't set, we have received all packets.
Now we just need to update the tail pointer to tell the hardware up to which point there are empty buffers in the ring.
We only update the tail pointer once to prevent unnecessary overhead from repeated PCIe transactions.

## Transmit flow

### Setup phase

During tx setup the driver initializes a number of tx queues.
Like rx queues, tx queues maintain a descriptor ring.
Head and tail pointers are also set to 0.
The tx setup is somewhat simpler than the rx setup, since there are no descriptors in the descriptor ring initially.
Descriptors will be added once the user program calls `tx_batch` with a number of packet buffers.

### Active phase

Once the user program calls `tx_batch` the driver performs two steps: cleanup and transmit.

#### Ring layout

```
+--------+ <- base address
| empty  |
+--------+
| empty  |
+--------+ <- base + clean_index
| dirty  |
+--------+
| dirty  |
+--------+ <- base + head
| unsent |
+--------+
| unsent |
+--------+
| unsent |
+--------+ <- base + tail
| empty  |
+--------+
| empty  |
+--------+
```

* Descriptors between `clean_index` and `head` are previously inserted packets that have been sent by the NIC.
* Descriptors between `head` and `tail` point to previously inserted packets that haven't been sent by the NIC.
* Descriptors between `tail` and `clean_index` are cleaned and ready-to-use.

#### Cleanup

Before inserting the outgoing packets into the descriptor ring, the driver needs to clean previously sent descriptors.
To improve performance, cleanup has to be done in batches of 32 descriptors.

For performance reasons we can't actually read the head pointer; reading NIC registers requires a full PCIe transaction.
The buffers, that may be ready to be cleaned, are the ones between `clean_index` and the tail pointer.
Of these the ones that have their DD bit set are ready to be cleaned.
However, it is inefficient to check every descriptor's DD bit so we only check every 32nd descriptor.
If this buffer's DD bit is set, all the buffer's before this one have also been sent out and can be cleaned.

#### Transmit

To transmit packets, the driver just walks the descriptor ring until it has sent all packets or hits a non-cleaned descriptor, setting each descriptor to one of the packets that are to be transmitted.
Once that's done the tail pointer register needs to be updated; ixy then returns the number of sent packets to the caller while ixy.ml returns the unsent packets themselves.
