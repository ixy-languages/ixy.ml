#include <linux/vfio.h>
#include <sys/ioctl.h>

#define CAML_NAME_SPACE

#include <caml/alloc.h>
#include <caml/bigarray.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/unixsupport.h>
#include <caml/fail.h>

#include "libixy-vfio.h"

#define FLAGS (CAML_BA_UINT8 | CAML_BA_C_LAYOUT | CAML_BA_EXTERNAL)

CAMLprim value ixy_pci_attach(value v_devname) {
    CAMLparam1(v_devname);
    const char *v = String_val(v_devname);
    CAMLreturn(Val_int(pci_attach(v)));
}

CAMLprim value ixy_enable_dma(value v_fd) {
    CAMLparam1(v_fd);
    pci_enable_dma(Int_val(v_fd));
    CAMLreturn(Val_unit);
}

CAMLprim value ixy_map_region(value v_fd) {
    CAMLparam1(v_fd);
    CAMLlocal1(v_result);
    size_t size;
    void *buffer = pci_map_region(Int_val(v_fd), VFIO_PCI_BAR0_REGION_INDEX, &size);
    v_result = caml_ba_alloc_dims(FLAGS, 1, buffer, size);
    CAMLreturn(v_result);
}

CAMLprim value ixy_allocate_dma(value v_size) {
    CAMLparam1(v_size);
    CAMLlocal1(v_result);
    size_t size = Long_val(v_size);
    void *buffer = pci_allocate_dma(Long_val(v_size));

    struct vfio_iommu_type1_dma_map dma_map = {
        .argsz = sizeof(dma_map),
        .flags = VFIO_DMA_MAP_FLAG_READ | VFIO_DMA_MAP_FLAG_WRITE,
        .vaddr = (uint64_t) buffer,
        .iova = (uint64_t) buffer,
        .size = Long_val(v_size)
    };

    if (ioctl(get_vfio_container(), VFIO_IOMMU_MAP_DMA, &dma_map) == -1) {
        caml_failwith("could not map dma vfio");
    }

    v_result = caml_ba_alloc_dims(FLAGS, 1, buffer, Long_val(v_size));
    CAMLreturn(v_result);
}
