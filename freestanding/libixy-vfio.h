/*
 * Adapted from libixy-vfio.
 * https://github.com/emmericp/ixy
 */

#include <inttypes.h>

int pci_attach(const char *pci_addr);

void pci_enable_dma(int vfio_fd);

void *pci_map_region(int vfio_fd, int region_index, size_t *size);

void *pci_allocate_dma(size_t size);

int get_vfio_container();
