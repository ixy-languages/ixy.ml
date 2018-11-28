open Core

val split : int64 -> int32 * int32

val mmap : Unix.File_descr.t -> Cstruct.t
