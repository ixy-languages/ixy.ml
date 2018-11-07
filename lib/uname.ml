type utsname = {
  sysname : string;
  nodename : string;
  release : string;
  version : string;
  machine : string
}

external uname : unit -> utsname = "ixy_uname"

let utsname = uname () (* only evaluate uname once *)

let sysname = utsname.sysname

let nodename = utsname.nodename

let release = utsname.release

let version = utsname.version

let machine = utsname.machine
