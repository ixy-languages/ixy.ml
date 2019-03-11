let split i64 =
  (Int64.to_int (Int64.logand i64 0xFFFFFFFFL)),
  (Int64.to_int (Int64.shift_right_logical i64 32))

(* 'Unix_cstruct.of_fd' doesn't map the file as shared. *)
let mmap fd =
  let genarray =
    Bigarray.(Unix.map_file fd char c_layout true [|-1|]) in
  Cstruct.of_bigarray (Bigarray.array1_of_genarray genarray)

let simulated =
  match Unix.getenv "IXY_SIMULATED" with
  | "" -> None
  | exception Not_found -> None
  | path ->
    if path.[String.length path - 1] = '/' then
      Some path
    else
      Some (path ^ "/")
