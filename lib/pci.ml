open Core

type hw = Memory.virt

let remove_driver pci_addr =
  let path =
    sprintf "/sys/bus/pci/devices/%s/driver/unbind" pci_addr in
  try
    let fd = Unix.(openfile ~mode:[O_WRONLY] path) in
    let buf = Bytes.unsafe_of_string_promise_no_mutation pci_addr in
    if Unix.(write fd ~buf) <> String.length pci_addr then
      Log.warn "failed to unload driver for device %s" pci_addr;
    Unix.close fd
  with Unix.Unix_error _ -> Log.debug "no driver loaded"

let enable_dma pci_addr =
  let path = sprintf "/sys/bus/pci/devices/%s/config" pci_addr in
  let fd = Unix.(openfile ~mode:[O_RDWR] path) in
  assert Unix.(lseek fd 4L ~mode:SEEK_SET = 4L);
  let buf = Bytes.create 2 in
  assert Unix.(read fd ~buf = 2);
  Bytes.(set buf 0 ((get buf 0) |> Char.to_int |> ( lor ) (1 lsl 2) |> Char.of_int_exn));
  assert Unix.(lseek fd 4L ~mode:SEEK_SET = 4L);
  assert Unix.(write fd ~buf = 2);
  Unix.close fd

let map_resource pci_addr =
  if Ixy_dbg.testing then
    Memory.malloc (1 lsl 21)
  else begin
    if
      try
        Scanf.sscanf pci_addr "%4x:%2x:%2x.%1x" (sprintf "%04x:%02x:%02x.%1x") <> pci_addr
      with
      | _ -> true
    then
      raise @@ Invalid_argument "pci_addr format must be xxxx:xx:xx.x";
    let path = sprintf "/sys/bus/pci/devices/%s/resource0" pci_addr in
    let fd = Unix.(openfile ~mode:[O_RDWR] path) in
    remove_driver pci_addr;
    enable_dma pci_addr;
    let stat = Unix.fstat fd in
    let size = Int.of_int64_exn stat.st_size in
    let hw = Memory.(mmap size [PROT_READ; PROT_WRITE] [MAP_SHARED] fd 0) in
    Unix.close fd; (* ixy doesn't do this but there shouldn't be a reason to keep fd around *)
    hw
  end

type pci_config = {
  vendor : int;
  device_id : int;
  device_class : int
}

let get_config pci_addr =
  if Ixy_dbg.testing then
    { vendor = 0; device_id = 0; device_class = 0 }
  else begin
    let path =
      sprintf "/sys/bus/pci/devices/%s/config" pci_addr in
    try
      let fd = Unix.(openfile path ~mode:[O_RDWR]) in
      let stat = Unix.fstat fd in
      let size = Int.of_int64_exn stat.st_size in
      let conf_space = Memory.(mmap size [PROT_READ; PROT_WRITE] [MAP_SHARED] fd 0) in
      Unix.close fd;
      let config =
        { vendor = Memory.read16 conf_space 0;
          device_id = Memory.read16 conf_space 2;
          device_class = (Memory.read32 conf_space 8) lsr 24
        } in
      Memory.munmap conf_space size;
      config
    with Unix.Unix_error (e, f, _) ->
      Log.error
        "couldn't open PCIe configuration space: %s %s"
        (Unix.Error.message e)
        f
  end
