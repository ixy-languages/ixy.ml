type utsname = {
  sysname : string;
  nodename : string;
  release : string;
  version : string;
  machine : string
}

external uname : unit -> utsname = "caml_uname"
