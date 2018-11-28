open Core

let split i64 =
  (Obj.magic Int64.(i64 land 0xFFFFFFFFL, i64 lsr 32) : int32 * int32)

(* we need our own version of 'Unix_cstruct.of_fd' to map the file as shared. *)
let mmap fd =
  let genarray =
    Bigarray.(Caml.Unix.map_file fd char c_layout true [|-1|]) in
  Cstruct.of_bigarray (Bigarray.array1_of_genarray genarray)
