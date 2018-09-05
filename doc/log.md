# Logging

ixy.ml has builtin logging functionality which is turned on by default.

If you wish to reduce logging simply set `Log.log_level` to `INFO`, `WARNING` or `ERROR`; if you wish to turn off logging entirely set it to `STFU`.

If you want to send your own debug, info, warning or error messages use the functions from the `Log` module.

If you don't want colored output set `Log.color` to `false`.

If you want to redirect the logging output use `Log.out_channel`.

## Example

```ocaml
let () =
  Ixy.Log.(color := false);
  Ixy.Log.(out_channel := stderr);
  Ixy.Log.(log_level := STFU); (* suppress all ixy messages during setup *)
  let dev = Ixy.create "0000:ab:cd.e" ~rxq:1 ~txq:1 in
  Ixy.Log.(log_level := INFO);
  while true do
    let rx = Ixy.rx_batch dev 0 in
    let n = Array.length rx in
    let rec loop offset =
      if offfset < rx then
        loop (Ixy.tx_batch dev 0 rx ~offset) in
    loop 0;
    Ixy.Log.info "echoed %d packets" n
  done
```
