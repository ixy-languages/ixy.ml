type t
(** Type of receive descriptors. *)

val sizeof : int
(** [sizeof] is the size of a receive descriptor in bytes. Equal to 16. *)

val split : int -> Cstruct.t -> t array
(** [split n cstruct] splits [cstruct] into [n] receive descriptors. *)

val dd : t -> bool
(** [dd rxd] returns [true] if [rxd]'s stat_dd bit is set,
    i.e. the corresponding buffer has been filled with a packet by the NIC. *)

val eop : t -> bool
(** [eop rxd] returns [true] if [rxd]'s stat_eop bit is set,
    i.e. the corresponding buffer has the contents of an entire packet.
    We don't support jumbo frames (yet?). *)

val size : t -> int
(** [size rxd] returns [rxd]'s size in bytes. *)

val reset : t -> Memory.pkt_buf -> unit
(** [reset rxd buf] resets [rxd] by resetting its flags and pointing
    it to the buffer [buf]. *)
