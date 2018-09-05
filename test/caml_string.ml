open Core

let to_hex ?(upper = false) str =
  let f i =
    let c = Char.to_int str.[i / 2] in
    let nibble = if i mod 2 = 0 then c lsr 4 else c land 0xf in
    let offset =
      if nibble < 0xa then 48 (* 0x0 <= nibble <= 0xf *)
      else if upper then 55 else 87 in
    Char.of_int_exn (nibble + offset) in
  String.init (String.length str * 2) ~f

let () =
  for i = 0 to 20 do
    let c_buf = Ixy.Memory.get_string () in
    if phys_equal c_buf Ixy.Memory.nullptr then
      failwith "nullpointer returned";
    let ptr = Ixy.Memory.offset_ptr c_buf 8 in
    let str = Ixy.Memory.make_ocaml_string ptr i in
    printf "i: %d\nstring: %s\nlen: %d\n\n" i (to_hex str) (String.length str)
  done
