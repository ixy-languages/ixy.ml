open Ixy.Uname

let () =
  Printf.printf
    "sysname: %s\nnodename: %s\nrelease: %s\nversion: %s\nmachine: %s\n"
    sysname
    nodename
    release
    version
    machine
