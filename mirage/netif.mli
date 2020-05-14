module Make (Pci : Mirage_pci.S) : sig
  include Mirage_net.S

  val connect : Pci.t -> t Lwt.t
end
