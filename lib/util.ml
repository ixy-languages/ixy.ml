let split i64 =
  (Obj.magic (Int64.logand i64 0xFFFFFFFFL) : int32),
  (Obj.magic (Int64.shift_right_logical i64 32) : int32)

(* 'Unix_cstruct.of_fd' doesn't map the file as shared. *)
let mmap fd =
  let genarray =
    Bigarray.(Unix.map_file fd char c_layout true [|-1|]) in
  Cstruct.of_bigarray (Bigarray.array1_of_genarray genarray)
