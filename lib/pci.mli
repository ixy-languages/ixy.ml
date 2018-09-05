open Core

type hw = Memory.virt

val map_resource : string -> hw

type pci_config = private {
  vendor : int;
  device_id : int;
  device_class : int
}

val get_config : string -> pci_config
