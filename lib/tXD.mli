type t
(** Type of transmit descriptors. *)

val sizeof : int
(** [sizeof] is the size of a transmit descriptor in bytes. Equal to 16. *)

val split : int -> Cstruct.t -> t array
(** [split n cstruct] splits [cstruct] into [n] transmit descriptors. *)

val dd : t -> bool
(** [dd txd] returns true if [txd]'s stat_dd bit is set,
    i.e. the packet that has been placed in the corresponding
    buffer was sent out by the NIC. *)

val reset : t -> Memory.pkt_buf -> unit
(** [reset txd buf] resets [txd] by resetting its flags and pointing
    it to the buffer [buf]. *)
