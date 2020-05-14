open Lwt.Infix

module Main (S: Mirage_net.S) = struct
  let start net0 =
    S.listen
      net0
      ~header_size:16
      (fun buf ->
        let size = Cstruct.len buf in
        S.write
          net0
          ~size
          (fun outbuf -> Cstruct.blit buf 0 outbuf 0 size; size)
        >>= function
        | Ok () -> Lwt.return_unit
        | Error e ->
          Logs.warn (fun f -> f "Error sending data: %a" S.pp_error e);
          Lwt.return_unit
      )
end
