#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/mman.h>
#include <errno.h>
#include <inttypes.h>
#include <string.h>
#include <fcntl.h> // TODO remove unnecessary imports

#define CAML_NAME_SPACE

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/signals.h>
#include <caml/gc.h>

// TODO delete this after testing
static uintptr_t virt_to_phys(void* virt) {
    long pagesize = sysconf(_SC_PAGESIZE);
    int fd = open("/proc/self/pagemap", O_RDONLY);
    // pagemap is an array of pointers for each normal-sized page
    lseek(fd, (uintptr_t) virt / pagesize * sizeof(uintptr_t), SEEK_SET);
    uintptr_t phy = 0;
    read(fd, &phy, sizeof(phy));
    close(fd);
    if (!phy) {
        fprintf(stderr, "failed to translate virtual address %p to physical address", virt);
        exit(1);
    }
    // bits 0-54 are the page number
    return (phy & 0x7fffffffffffffULL) * pagesize + ((uintptr_t) virt) % pagesize;
}

CAMLprim value caml_virt_to_phys(value virt) {
    CAMLparam1(virt);
    uintptr_t phys = virt_to_phys((void *) virt);
    CAMLreturn(caml_copy_int64(phys));
}

CAMLprim value caml_int64_of_addr(value virt) {
    CAMLparam1(virt);
    CAMLreturn(caml_copy_int64((uint64_t) virt));
}

CAMLprim value caml_mlock(value ptr, value size) {
    CAMLparam2(ptr, size);
    if (mlock((void *) ptr, Int_val(size))) {
        caml_failwith("Error: mlock()");
    }
    CAMLreturn(Val_unit);
}

CAMLprim value caml_munlock(value ptr, value size) {
    CAMLparam2(ptr, size);
    if (munlock((void *) ptr, Int_val(size))) {
        caml_failwith("Error: munlock()");
    }
    CAMLreturn(Val_unit);
}

static int prot_flag_table[4] = {
    PROT_NONE,
    PROT_READ,
    PROT_WRITE,
    PROT_EXEC
};

static int map_flag_table[15] = {
    MAP_SHARED,
    MAP_PRIVATE,
    MAP_FILE,
    MAP_FIXED,
    MAP_ANONYMOUS,
#ifdef __linux__
    MAP_32BIT,
    MAP_GROWSDOWN,
    MAP_HUGETLB,
    MAP_LOCKED,
    MAP_NONBLOCK,
    MAP_NORESERVE,
    MAP_POPULATE,
    MAP_STACK,
#else
    0, 0, 0, 0, 0, 0, 0, 0,
#endif
#ifdef __APPLE__
    MAP_NOCACHE,
    MAP_HASSEMAPHORE
#else
    0, 0
#endif
};

CAMLprim value caml_mmap(value size, value prot_list, value flags_list, value fd, value offset) {
    CAMLparam5(size, prot_list, flags_list, fd, offset);
    int prot = caml_convert_flag_list(prot_list, prot_flag_table);
    int flags = caml_convert_flag_list(flags_list, map_flag_table);
    caml_enter_blocking_section(); // not sure if needed
    void *result = mmap(NULL, Int_val(size), prot, flags, Int_val(fd), Long_val(offset));
    caml_leave_blocking_section();
    if (result == MAP_FAILED) { // TODO make this return a Unix.error
        switch(errno) {
            case EACCES:
                caml_failwith("could not mmap: EACCES");
                break;
            case EBADF:
                caml_failwith("could not mmap: EBADF");
                break;
            case EINVAL:
                caml_failwith("could not mmap: EINVAL");
                break;
            case ENODEV:
                caml_failwith("could not mmap: ENODEV");
                break;
            case ENOMEM:
                caml_failwith("could not mmap: ENOMEM");
                break;
            case ENXIO:
                caml_failwith("could not mmap: ENXIO");
                break;
            case EOVERFLOW:
                caml_failwith("could not mmap: EOVERFLOW");
                break;
        }
    }
    CAMLreturn((value) result);
}

CAMLprim value caml_munmap(value ptr, value size) {
    CAMLparam2(ptr, size);
    if (munmap((void *) ptr, size)) {
        caml_failwith("could not munmap");
    }
    CAMLreturn(Val_unit);
}

CAMLprim value caml_test_string(value string) {
    CAMLparam1(string);
    printf("String: \"%s\"\nLength: %ld\n", String_val(string), caml_string_length(string));
    CAMLreturn(Val_unit);
}

CAMLprim value caml_read64(value virt, value offset) {
    CAMLparam2(virt, offset);
    CAMLreturn(caml_copy_int64(*((volatile uint64_t *) (((char *) virt) + Long_val(offset)))));
}

CAMLprim value caml_write64(value virt, value offset, value v) {
    CAMLparam3(virt, offset, v);
    *((volatile uint64_t *) (((char *) virt) + Long_val(offset))) = Int64_val(v);
    CAMLreturn(Val_unit);
}

CAMLprim value caml_read32(value virt, value offset) {
    CAMLparam2(virt, offset);
    CAMLreturn(Val_long(*((volatile uint32_t *) (((char *) virt) + Long_val(offset)))));
}

CAMLprim value caml_write32(value virt, value offset, value v) {
    CAMLparam3(virt, offset, v);
    *((volatile uint32_t *) (((char *) virt) + Long_val(offset))) = (uint32_t) Long_val(v);
    CAMLreturn(Val_unit);
}

CAMLprim value caml_read16(value virt, value offset) {
    CAMLparam2(virt, offset);
    CAMLreturn(Val_long(*((volatile uint16_t *) (((char *) virt) + Long_val(offset)))));
}

CAMLprim value caml_write16(value virt, value offset, value v) {
    CAMLparam3(virt, offset, v);
    *((volatile uint16_t *) (((char *) virt) + Long_val(offset))) = (uint16_t) Long_val(v);
    CAMLreturn(Val_unit);
}

CAMLprim value caml_read8(value virt, value offset) {
    CAMLparam2(virt, offset);
    CAMLreturn(Val_long(*((volatile uint8_t *) (((char *) virt) + Long_val(offset)))));
}

CAMLprim value caml_write8(value virt, value offset, value v) {
    CAMLparam3(virt, offset, v);
    *((volatile uint8_t *) (((char *) virt) + Long_val(offset))) = (uint8_t) Long_val(v);
    CAMLreturn(Val_unit);
}

CAMLprim value caml_offset_ptr(value virt, value offset) {
    CAMLparam2(virt, offset);
    CAMLreturn((value) (((char *) virt) + Long_val(offset)));
}

CAMLprim value caml_getnullptr(value unit) {
    CAMLparam1(unit);
    CAMLreturn((value) NULL);
}

// put an OCaml string header in front of virt and pad appropriately
// len is in bytes from virt
// similar to caml_alloc_string() in ocaml/runtime/alloc.c
CAMLprim value caml_make_ocaml_string(value virt, value len) {
    CAMLparam2(virt, len);
    mlsize_t wosize = (Long_val(len) + sizeof(value)) / sizeof(value);
    Hd_val(virt) = Make_header(wosize, String_tag, Caml_black);

    uint8_t num_null_bytes = 7 - (Long_val(len) % sizeof(value));

    Byte(virt, Bsize_wsize(wosize) - 1) = num_null_bytes;

    for (int i = 2; i <= num_null_bytes; i++)
        Byte(virt, Bsize_wsize(wosize) - i) = 0;

    CAMLreturn(virt);
}

CAMLprim value caml_get_string(value unit) {
    CAMLparam1(unit);
    char *ptr = (char *) malloc(256);

    for (int i = 0; i < 256; i++)
        ptr[i] = 0xff;

    CAMLreturn((value) ptr);
}

CAMLprim value caml_dump_memory(value file, value virt, value len) {
    CAMLparam3(file, virt, len);
    printf("dumping %#lx bytes at virt %#018llx\n", Long_val(len), (uint64_t) virt);
    if (!caml_string_is_c_safe(file))
        caml_failwith("the filename is not C safe, i.e. contains null bytes");

    int fd = open((char *) file, O_CREAT | O_RDWR, S_IRWXU | S_IRWXG | S_IRWXO);
    if (fd == -1) {
        char msg[10000];
        snprintf(msg, 10000, "couldn't open file %s", String_val(file));
        caml_failwith(msg);
    }
    if (Long_val(len) != write(fd, String_val(virt), Long_val(len))) {
        caml_failwith("couldn't write the whole buffer");
    }
    close(fd);
    CAMLreturn(Val_unit);
}

CAMLprim value caml_malloc(value len) {
    CAMLparam1(len);
    void *mem = malloc(Long_val(len));
    if (!mem)
        caml_failwith("couldn't malloc");
    CAMLreturn((value) mem);
}
