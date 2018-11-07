type t
(** Type of transmit descriptors. *)

val sizeof : int
(** [sizeof] is the size of a transmit descriptor in bytes. Equal to 16. *)

val split : Cstruct.t -> t array
(** [split cstruct] splits [cstruct] into a number of transmit descriptors.
    Fails if [cstruct]'s length is not divisible by 16. *)

val dd : t -> bool
(** [dd txd] returns true if [txd]'s stat_dd bit is set,
    i.e. the packet that has been placed in the corresponding
    buffer was sent out by the NIC. *)

val reset : t -> Memory.pkt_buf -> unit
(** [reset txd buf] resets [txd] by resetting its flags and pointing
    it to the buffer [buf]. *)
