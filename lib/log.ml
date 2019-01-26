open Printf

type log_level =
  | STFU
  | ERROR
  | WARNING
  | INFO
  | DEBUG

module Color = struct
  let red = "\x1b[31m"
  let green = "\x1b[32m"
  let yellow = "\x1b[33m"
  let blue = "\x1b[34m"
  let magenta = "\x1b[35m"
  let cyan = "\x1b[36m"
  let reset = "\x1b[0m"
end

let color = ref true

let out_channel = ref stdout

let log_level = ref DEBUG

let ignore_fmt fmt =
  ksprintf ignore fmt

let error fmt =
  if !log_level >= ERROR then
    let label : (string -> unit, out_channel, unit) format =
      if !color then
        "\x1b[31m[ERROR] %s\x1b[0m\n%!" (* red *)
      else
        "[ERROR] %s\n%!" in
    ksprintf (fun msg -> fprintf !out_channel label msg; exit 1) fmt
  else
    ksprintf (fun _ -> exit 1) fmt

let errors errs =
  let error err =
    let label : (string -> unit, out_channel, unit) format =
      if !color then
        "\x1b[31m[ERROR] %s\x1b[0m\n%!" (* red *)
      else
        "[ERROR] %s\n%!" in
    fprintf !out_channel label err in
  if !log_level >= ERROR then
    List.iter error errs;
  exit 1

let warn fmt =
  if !log_level >= WARNING then
    let label : (string -> unit, out_channel, unit) format =
      if !color then
        "\x1b[33m[WARNING] %s\x1b[0m\n%!" (* yellow *)
      else
        "[WARNING] %s\n%!" in
    ksprintf (fun msg -> fprintf !out_channel label msg) fmt
  else
    ignore_fmt fmt

let info fmt =
  if !log_level >= INFO then
    let label : (string -> unit, out_channel, unit) format =
      if !color then
        "\x1b[36m[INFO] %s\x1b[0m\n%!" (* cyan *)
      else
        "[INFO] %s\n%!" in
    ksprintf (fun msg -> fprintf !out_channel label msg) fmt
  else
    ignore_fmt fmt

let debug fmt =
  if !log_level >= DEBUG then
    let label : (string -> unit, out_channel, unit) format =
      if !color then
        "\x1b[35m[DEBUG] %s\x1b[0m\n%!" (* magenta *)
      else
        "[DEBUG] %s\n%!" in
    ksprintf (fun msg -> fprintf !out_channel label msg) fmt
  else
    ignore_fmt fmt

let confirm ~default fmt =
  let f fmt =
    let prompt () =
      let label : (string -> string -> unit, out_channel, unit) format =
        if !color then
          "\x1b[32m[CONFIRM] %s [%s] \x1b[0m%!" (* green *)
        else
          "[CONFIRM] %s [%s] %!" in
      printf label fmt (if default then "Y/n" else "y/N") in
    let rec loop () =
      prompt ();
      match String.lowercase_ascii (input_line stdin) with
      | "y" | "yes" -> true
      | "n" | "no" -> false
      | "" -> default
      | exception End_of_file -> loop ()
      | _ -> loop () in
    loop () in
  ksprintf f fmt
