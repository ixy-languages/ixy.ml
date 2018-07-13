open Core

let init_str = "blablablablab\n"
let msg = "Hello, world!\n"

let init file =
  let oc = Out_channel.create file in
  Out_channel.output_string oc init_str;
  Out_channel.close oc;
  Printf.printf "initialized %s\n" file

let verify file =
  let ic = In_channel.create file in
  let str = In_channel.input_all ic in
  In_channel.close ic;
  str = msg

let () =
  if Array.length Sys.argv <> 2 then
    failwith (Printf.sprintf "Usage: %s <file>" Sys.argv.(0));
  let file = Sys.argv.(1) in
  init file;
  let fd = Unix.openfile ~mode:Unix.[O_RDWR] file in
  let size = String.length init_str in
  let virt = Ixy.Memory.(mmap size [PROT_WRITE; PROT_READ] [MAP_SHARED] fd 0) in
  for i = 0 to (String.length msg) - 1 do
    Ixy.Memory.write8 virt i (Char.to_int msg.[i])
  done;
  Ixy.Memory.munmap virt size;
  Unix.close fd;
  if verify file then begin
    Out_channel.print_endline "mmap successful, deleting";
    Unix.remove file
  end else begin
    Out_channel.print_endline "mmap unsuccessful, not deleting"
  end
