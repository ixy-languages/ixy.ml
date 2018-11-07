open Core

let testing = Uname.sysname <> "Linux" (* return dummy values on macOS *)

let () =
  if testing then Log.info "testing mode activated"
