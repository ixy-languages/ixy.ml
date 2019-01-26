type utsname = {
  sysname : string;
  nodename : string;
  release : string;
  version : string;
  machine : string
}

external uname : unit -> utsname = "ixy_uname"

let { sysname; nodename; release; version; machine } =
  uname () (* only evaluate uname once *)
