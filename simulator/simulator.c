#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <inttypes.h>
#include <errno.h>
#include <signal.h>
#include <sys/syslimits.h>
#include <pthread.h>
#include <stdbool.h>
#include <time.h>
#include <sys/stat.h>
#include <dirent.h>
#include <string.h>

#include "log.h"
#include "regs.h"
#include "ixgbe_type.h"

char *progname;

void usage() {
    printf("Usage: %s <pci_addresses>", progname);
    exit(1);
}

void mysleep(long secs, long nsecs) {
    struct timespec rem = { .tv_sec = secs, .tv_nsec = nsecs };
    do {
        nanosleep(&rem, &rem);
    } while (rem.tv_sec != 0 && rem.tv_nsec != 0);
}

#define SIM_PATH "/Volumes/RAMDisk/"
#define IXY_PREFIX "ixy.ml-0x"

void clean(void) {
    DIR *dirp = opendir(SIM_PATH);
    if (!dirp)
        error("could not open simpath: " SIM_PATH);
    int len = 25;
    struct dirent *dp;
    while ((dp = readdir(dirp)) != NULL) {
        if (dp->d_namlen == len && !strncmp(dp->d_name, IXY_PREFIX, sizeof(IXY_PREFIX) - 1)) {
            char del_path[PATH_MAX];
            snprintf(del_path, PATH_MAX, SIM_PATH "%s", dp->d_name);
            if (unlink(del_path)) {
                warn("could not delete temp file %s (%s)", del_path, strerror(errno));
            } else {
                info("deleted temp file %s", del_path);
            }
        } else {
            info("not cleaning %s", dp->d_name);
        }
    }
}

#define REGISTER_SIZE 524288

#define MAX_QUEUES 64

typedef struct {
    // index of the queue
    int id;
    // shared NIC registers
    uint8_t *regs;
    // descriptor ring file; set by queue thread
    int ring_fd;
    // descriptor ring; set by queue thread
    uint8_t *ring;
} rxq_info;

typedef struct {
    // index of the queue
    int id;
    // shared NIC registers
    uint8_t *regs;
    // descriptor ring file; set by queue thread
    int ring_fd;
    // descriptor ring; set by queue thread
    uint8_t *ring;
} txq_info;

typedef struct {
    char *pci;
    uint8_t *regs;
    bool launched;
    char reg_path[PATH_MAX];
    char dir_path[PATH_MAX];
    pthread_t thread;
    int num_rxqs;
    pthread_t rxqs[MAX_QUEUES];
    rxq_info rxqs_info[MAX_QUEUES];
    int num_txqs;
    pthread_t txqs[MAX_QUEUES];
    txq_info txqs_info[MAX_QUEUES];
} nic_thread_info;

nic_thread_info *nics;
int num_nics;

void stop(int sig) {
    info("shutting down");
    for (int i = 0; i < num_nics; i++) {
        nic_thread_info *nic = &nics[i];
        if (nic->launched) {
            for (int q = 0; q < nic->num_rxqs; q++) {
                if (pthread_cancel(nic->rxqs[q]))
                    warn("could not cancel rxq %s:%d", nic->pci, q);
            }

            for (int q = 0; q < nic->num_txqs; q++) {
                if (pthread_cancel(nic->txqs[q]))
                    warn("could not cancel txq %s:%d", nic->pci, q);
            }

            if (pthread_cancel(nic->thread))
                warn("could not cancel nic_thread %s", nic->pci);

            if (munmap(nic->regs, REGISTER_SIZE))
                warn("could not unmap register for nic %s", nic->pci);
            if (unlink(nic->reg_path))
                warn("could not remove %s", nic->reg_path);
            if (rmdir(nic->dir_path))
                warn("could not delete dir %s", nic->dir_path);
        }
    }
    exit(0);
}

void *rxq_thread(void *args) {
    rxq_info *info = (rxq_info *) args;
    int id = info->id;
    info("rxq %d running", id);

    uint8_t *regs = info->regs;
    uintptr_t hi = get_reg32(regs, IXGBE_RDBAH(id));
    uintptr_t lo = get_reg32(regs, IXGBE_RDBAL(id));
    uintptr_t desc_addr = (hi << 32) + lo;
    info("rxq %d found descriptors at %#018lx", id, desc_addr);

    char ring_path[PATH_MAX];
    snprintf(ring_path, PATH_MAX, SIM_PATH IXY_PREFIX "%016lx", desc_addr);
    info("mapping %s", ring_path);
    mysleep(3, 0);
    if ((info->ring_fd = open(ring_path, O_RDWR, S_IRWXU)))
        error("could not open %s '%s'", ring_path, strerror(errno));
    int rdlen = get_reg32(regs, IXGBE_RDLEN(id));

    info->ring = mmap(NULL, rdlen * sizeof(union ixgbe_adv_rx_desc), PROT_READ | PROT_WRITE, MAP_SHARED, info->ring_fd, 0);
    if (info->ring == MAP_FAILED)
        error("rxq %d could not mmap descriptor ring %s", id, ring_path);
    else
        info("mapped rx ring for rxq %d", id);

    int rdt = get_reg32(regs, IXGBE_RDT(id)), rdh = get_reg32(regs, IXGBE_RDH(id));

    mysleep(1000, 0);
    return NULL;
}

void *txq_thread(void *args) {
    txq_info *info = (txq_info *) args;
    info("txq %d running", info->id);
    uintptr_t hi = get_reg32(info->regs, IXGBE_TDBAH(info->id));
    uintptr_t lo = get_reg32(info->regs, IXGBE_TDBAL(info->id));
    uintptr_t desc_addr = (hi << 32) + lo;
    info("txq %d found descriptors at %#018lx", info->id, desc_addr);

    mysleep(1000, 0);
    return NULL;
}

void *nic_thread(void *args) {
    nic_thread_info *nic = (nic_thread_info *) args;

    snprintf(nic->dir_path, PATH_MAX, SIM_PATH "%s", nic->pci);
    if (mkdir(nic->dir_path, S_IRWXU) && errno != EEXIST)
        error("could not create directory '%s'", nic->dir_path);

    char *reg_path = nic->reg_path;
    snprintf(reg_path, PATH_MAX, "%s/resource0", nic->dir_path);
    int reg_fd;
    if ((reg_fd = open(reg_path, O_CREAT | O_RDWR, S_IRWXU)) == -1)
        error("could not open %s", reg_path);

    if (ftruncate(reg_fd, REGISTER_SIZE))
        error("could not resize %s", reg_path);

    if ((nic->regs = (uint8_t *) mmap(NULL, REGISTER_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, reg_fd, 0)) == MAP_FAILED)
        error("could not mmap %s", reg_path);

    if (close(reg_fd))
        warn("could not close %s", reg_path);

    uint8_t *regs = nic->regs;
    wait_set_reg32(regs, IXGBE_CTRL, IXGBE_CTRL_RST_MASK);
    clear_flags32(regs, IXGBE_CTRL, IXGBE_CTRL_RST_MASK);
    info("reset done");

    set_flags32(regs, IXGBE_EEC, IXGBE_EEC_ARD);
    set_flags32(regs, IXGBE_RDRXCTL, IXGBE_RDRXCTL_DMAIDONE);

    info("setting link up (10 Gbit/s)");
    set_flags32(regs, IXGBE_LINKS, IXGBE_LINKS_UP | IXGBE_LINKS_SPEED_10G_82599);

    // TODO what if we don't create MAX_QUEUES queues
    while (nic->num_rxqs < MAX_QUEUES || nic->num_txqs < MAX_QUEUES) {
        for (int i = nic->num_rxqs; i < MAX_QUEUES; i++) {
            if (get_reg32(regs, IXGBE_RXDCTL(i)) & IXGBE_RXDCTL_ENABLE && !nic->rxqs[i]) {
                info("rx queue %d activated", i);
                nic->rxqs_info[i].id = i;
                nic->rxqs_info[i].regs = regs;

                if (pthread_create(&nic->rxqs[i], NULL, rxq_thread, &nic->rxqs_info[i]))
                    error("could not create rxq_thread %d", i);
                nic->num_rxqs++;
            }
        }

        for (int i = nic->num_txqs; i < MAX_QUEUES; i++) {
            if (get_reg32(regs, IXGBE_TXDCTL(i)) & IXGBE_TXDCTL_ENABLE && !nic->txqs[i]) {
                info("tx queue %d activated", i);
                nic->txqs_info[i].id = i;
                nic->txqs_info[i].regs = regs;

                if (pthread_create(&nic->txqs[i], NULL, txq_thread, &nic->txqs_info[i]))
                    error("could not create txq_thread %d", i);
                nic->num_txqs++;
            }
        }

        mysleep(0, 1000000);
    };

    for (int i = 0; i < nic->num_rxqs; i++) {
        if (pthread_join(nic->rxqs[i], NULL))
            warn("could not join %s rxq %d", nic->pci, i);
    }

    for (int i = 0; i < nic->num_txqs; i++) {
        if (pthread_join(nic->txqs[i], NULL))
            warn("could not join %s txq %d", nic->pci, i);
    }

    return NULL;
}

int main(int argc, char **argv) {
    progname = argv[0];
    if (argc < 2)
        usage();

    warn("make sure to run this simulator on a memory-backed filesystem");
    warn("otherwise this will chew through your SSD and/or be slow");

    clean();

    num_nics = argc - 1;
    nics = calloc(num_nics, sizeof(nic_thread_info));
    if (!nics)
        error("could not allocate nic_thread_info structs");

    for (int i = 0; i < num_nics; i++) {
        info("creating simulated nic %s", argv[i + 1]);
        nics[i].pci = argv[i + 1];

        if (pthread_create(&nics[i].thread, NULL, nic_thread, &nics[i]))
            error("could not create nic_thread %d", i);
        nics[i].launched = true;
    }

    signal(SIGINT, stop);

    for (int i = 0; i < num_nics; i++) {
        if (pthread_join(nics[i].thread, NULL))
            warn("could not join nic_thread %d", i);
    }
    return 0;
}
