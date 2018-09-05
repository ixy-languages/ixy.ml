let () =
  let Ixy.Uname.{ sysname; nodename; release; version; machine } =
    Ixy.Uname.uname () in
  Printf.printf
    "sysname: %s\nnodename: %s\nrelease: %s\nversion: %s\nmachine: %s\n"
    sysname
    nodename
    release
    version
    machine
