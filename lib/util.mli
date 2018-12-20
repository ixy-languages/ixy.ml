open Core

val split : int64 -> int32 * int32
(** [split i64] splits [i64] into its lower and upper 32 bits. *)

val mmap : Unix.File_descr.t -> Cstruct.t
(** [mmap fd] memory-maps [fd] as shared. *)

val wait : float -> unit
(** [wait delay] waits [delay] seconds. *)
