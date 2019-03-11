val split : int64 -> int * int
(** [split i64] splits [i64] into its lower and upper 32 bits. *)

val mmap : Unix.file_descr -> Cstruct.t
(** [mmap fd] memory-maps [fd] as shared. *)

val simulated : string option
(** [simulated] contains the path (with a guaranteed trailing '/') to the
    simulator if ixy is running in simulation mode. [None] otherwise. *)
