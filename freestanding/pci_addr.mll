let digit = ['0' - '9' 'a' - 'f']

let dom = digit digit digit digit

let bus = digit digit

let dev = digit digit

let func = digit

let sep = [':' '.']?

rule check =
  parse
  | (dom as dom) sep (bus as b) sep (dev as d) sep (func as f) eof
    { Some (Printf.sprintf "%s:%s:%s.%c" dom b d f) }
  | (bus as b) sep (dev as d) sep (func as f) eof
    { Some (Printf.sprintf "0000:%s:%s.%c" b d f) }
  | _
    { None }

{
let check str =
  let lower = String.lowercase_ascii str in
  let lexbuf = Lexing.from_string lower in
  check lexbuf
}
