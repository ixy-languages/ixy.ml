type t
(** Type of PCIe addresses. *)

val of_string : string -> t option
(** [of_string addr] parses [addr] and returns the corresponding [t].
    Returns [None] if [addr] is not a valid PCIe address. *)

val to_string : t -> string
(** [to_string t] returns the string representation of [t]. *)

type hw = Cstruct.t
(** Type of register files (also called [hw] in the linux ixgbe driver). *)

val map_resource : t -> hw
(** [map_resource pci_addr] *)

type pci_config = private {
  vendor : int;
  device_id : int;
  class_code : int;
  subclass : int;
  prog_if : int
}
(** Type of the PCIe configuration space. *)

val get_config : t -> pci_config
(** [get_config t] returns the PCIe configuration space for [t]. *)

val vendor_intel : int
(** Intel's vendor ID ([0x8086] in little endian). *)
