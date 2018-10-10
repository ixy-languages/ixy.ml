open Core

let testing = (Uname.uname ()).sysname <> "Linux" (* return dummy values on macOS *)

let () =
  if testing then Log.info "testing mode activated"
