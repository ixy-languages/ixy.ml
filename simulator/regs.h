static inline void set_reg32(uint8_t* addr, int reg, uint32_t value) {
    __asm__ volatile ("" : : : "memory");
    *((volatile uint32_t*) (addr + reg)) = value;
}

static inline uint32_t get_reg32(const uint8_t* addr, int reg) {
    __asm__ volatile ("" : : : "memory");
    return *((volatile uint32_t*) (addr + reg));
}

static inline void set_flags32(uint8_t* addr, int reg, uint32_t flags) {
    set_reg32(addr, reg, get_reg32(addr, reg) | flags);
}

static inline void clear_flags32(uint8_t* addr, int reg, uint32_t flags) {
    set_reg32(addr, reg, get_reg32(addr, reg) & ~flags);
}

static inline void wait_clear_reg32(const uint8_t* addr, int reg, uint32_t mask) {
    __asm__ volatile ("" : : : "memory");
    uint32_t cur = 0;
    while (cur = *((volatile uint32_t*) (addr + reg)), (cur & mask) != 0) {
        usleep(10000);
        __asm__ volatile ("" : : : "memory");
    }
}

static inline void wait_set_reg32(const uint8_t* addr, int reg, uint32_t mask) {
    __asm__ volatile ("" : : : "memory");
    uint32_t cur = 0;
    while (cur = *((volatile uint32_t*) (addr + reg)), (cur & mask) != mask) {
        usleep(10000);
        __asm__ volatile ("" : : : "memory");
    }
}
