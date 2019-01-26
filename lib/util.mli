val split : int64 -> int32 * int32
(** [split i64] splits [i64] into its lower and upper 32 bits. *)

val mmap : Unix.file_descr -> Cstruct.t
(** [mmap fd] memory-maps [fd] as shared. *)
