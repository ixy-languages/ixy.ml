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

#include "log.h"
#include "regs.h"
#include "ixgbe_type.h"

char *progname;

void usage() {
    printf("Usage: %s <pci_addresses>", progname);
    exit(1);
}

void mysleep(long secs, long nsecs) {
    struct timespec rqtp = { .tv_sec = secs, .tv_nsec = nsecs };
    nanosleep(&rqtp, NULL);
}

#define REGISTER_SIZE 524288

#define MAX_QUEUES 64

typedef struct {
    char *pci;
    int reg_fd;
    uint8_t *regs;
    bool launched;
    char reg_path[PATH_MAX];
    char dir_path[PATH_MAX];
    pthread_t thread;
    pthread_t rxqs[MAX_QUEUES];
    pthread_t txqs[MAX_QUEUES];
} nic_thread_info;

nic_thread_info *nics;
int num_nics;

void stop(int sig) {
    for (int i = 0; i < num_nics; i++) {
        nic_thread_info *nic = &nics[i];
        if (nic->launched) {
            for (int i = 0; i < MAX_QUEUES; i++) {
                if (nic->rxqs[i] && pthread_cancel(nic->rxqs[i]))
                    error("could not cancel rxq %s:%d", nic->pci, i);
                if (nic->txqs[i] && pthread_cancel(nic->txqs[i]))
                    error("could not cancel txq %s:%d", nic->pci, i);
            }
            if (pthread_cancel(nic->thread))
                error("could not cancel nic_thread %s", nic->pci);

            munmap(nic->regs, REGISTER_SIZE);
            close(nic->reg_fd);
            unlink(nic->reg_path);
        }
    }
    exit(0);
}

void *rxq_thread(void *args) {
    int rxq_id = *((int *) args);
    free(args);
    info("rxq %d running", rxq_id);
    mysleep(1000, 0);
    return NULL;
}

void *txq_thread(void *args) {
    int txq_id = *((int *) args);
    free(args);
    info("txq %d running", txq_id);
    mysleep(1000, 0);
    return NULL;
}

void *nic_thread(void *args) {
    nic_thread_info *nic = (nic_thread_info *) args;

    snprintf(nic->dir_path, PATH_MAX, "/tmp/ixy-simulator/%s", nic->pci);
    if (mkdir(nic->dir_path, S_IRWXU) && errno != EEXIST)
        error("could not create directory '%s'", nic->dir_path);

    char *reg_path = nic->reg_path;
    snprintf(reg_path, PATH_MAX, "%s/resource0", nic->dir_path);
    if ((nic->reg_fd = open(reg_path, O_CREAT | O_RDWR, S_IRWXU)) == -1)
        error("could not open %s", reg_path);

    if (ftruncate(nic->reg_fd, REGISTER_SIZE))
        error("could not resize %s", reg_path);

    if ((nic->regs = (uint8_t *) mmap(NULL, REGISTER_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, nic->reg_fd, 0)) == MAP_FAILED)
        error("could not mmap %s", reg_path);

    if (close(nic->reg_fd))
        error("could not close %s", reg_path);

    uint8_t *regs = nic->regs;
    wait_set_reg32(regs, IXGBE_CTRL, IXGBE_CTRL_RST_MASK);
    clear_flags32(regs, IXGBE_CTRL, IXGBE_CTRL_RST_MASK);
    info("reset done");
    set_flags32(regs, IXGBE_EEC, IXGBE_EEC_ARD);
    set_flags32(regs, IXGBE_RDRXCTL, IXGBE_RDRXCTL_DMAIDONE);
    set_flags32(regs, IXGBE_LINKS, IXGBE_LINKS_UP | IXGBE_LINKS_SPEED_10G_82599);

    int num_rxqs = 0, num_txqs = 0;
    // TODO what if we don't create MAX_QUEUES queues
    while (num_rxqs < MAX_QUEUES || num_txqs < MAX_QUEUES) {
        for (int i = 0; i < MAX_QUEUES; i++) {
            if (get_reg32(regs, IXGBE_RXDCTL(i)) & IXGBE_RXDCTL_ENABLE && !nic->rxqs[i]) {
                info("rx queue %d activated", i);
                int *rxq_id = malloc(sizeof(int));
                if (!rxq_id)
                    error("could not malloc");
                *rxq_id = i;
                num_rxqs++;
                if (pthread_create(&nic->rxqs[i], NULL, rxq_thread, (void *) rxq_id))
                    error("could not create rxq_thread %d", i);
            }
            if (get_reg32(regs, IXGBE_TXDCTL(i)) & IXGBE_TXDCTL_ENABLE && !nic->txqs[i]) {
                info("tx queue %d activated", i);
                int *txq_id = malloc(sizeof(int));
                if (!txq_id)
                    error("could not malloc");
                *txq_id = i;
                num_txqs++;
                if (pthread_create(&nic->txqs[i], NULL, txq_thread, (void *) txq_id))
                    error("could not create txq_thread %d", i);
            }
        }
        mysleep(0, 1000000);
    };

    for (int i = 0; i < num_rxqs; i++) {
        if (pthread_join(nic->rxqs[i], NULL))
            error("could not join %s rxq %d", nic->pci, i);
    }
    for (int i = 0; i < num_txqs; i++) {
        if (pthread_join(nic->txqs[i], NULL))
            error("could not join %s txq %d", nic->pci, i);
    }
    return NULL;
}

int main(int argc, char **argv) {
    progname = argv[0];
    if (argc < 2)
        usage();

    num_nics = argc - 1;
    nics = calloc(num_nics, sizeof(nic_thread_info));
    if (!nics)
        error("could not allocate nic_thread_info structs");

    for (int i = 0; i < num_nics; i++) {
        info("creating simulated nic %s", argv[i + 1]);
        nics[i].pci = argv[i + 1];
        if (pthread_create(&nics[i].thread, NULL, nic_thread, &nics[i]))
            error("could not create nic_thread %d", i);
    }

    for (int i = 0; i < num_nics; i++) {
        if (pthread_join(nics[i].thread, NULL))
            error("could not join nic_thread %d", i);
    }
    return 0;
}
