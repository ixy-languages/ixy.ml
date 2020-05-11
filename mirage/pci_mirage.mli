module Make (Pci : Mirage_pci.S) : sig
  type t = Pci.t
  include Ixy_core.Ixy_pci.S with type t := Pci.t
end
