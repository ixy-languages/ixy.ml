open Mirage

let main = foreign "Unikernel.Main" (network @-> job)

let () =
  register "echo" [
    main $ default_network
  ]
