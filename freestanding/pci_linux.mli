include Ixy_core.Ixy_pci.S

val of_string : string -> t option
(** [of_string addr] parses [addr] and returns the corresponding [t].
    Returns [None] if [addr] is not a valid PCIe address. *)

val pagesize : int
