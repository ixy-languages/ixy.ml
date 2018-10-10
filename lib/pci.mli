open Core

type hw = Memory.virt

val map_resource : string -> hw

type pci_config = private {
  vendor : int;
  device_id : int;
  class_code : int;
  subclass : int;
  prog_if : int
}

val get_config : string -> pci_config

val vendor_intel : int
