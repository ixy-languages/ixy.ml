#include <stdio.h>
#include <stdlib.h>

#define COLOR_RED "\x1b[31m"
#define COLOR_GREEN "\x1b[32m"
#define COLOR_YELLOW "\x1b[33m"
#define COLOR_BLUE "\x1b[34m"
#define COLOR_MAGENTA "\x1b[35m"
#define COLOR_CYAN "\x1b[36m"
#define COLOR_RESET "\x1b[0m"

#define error(fmt, ...)\
    do {\
        fprintf(stderr, COLOR_RED "[ERROR (%s, %s:%d)] " fmt COLOR_RESET "\n", __func__, __FILE__, __LINE__, ##__VA_ARGS__);\
        exit(EXIT_FAILURE);\
    } while (0)

#define warn(fmt, ...)\
    do {\
        fprintf(stderr, COLOR_YELLOW "[WARNING] " fmt COLOR_RESET "\n", ##__VA_ARGS__);\
    } while (0)

#define info(fmt, ...)\
    do {\
        fprintf(stdout, COLOR_CYAN "[INFO] " fmt COLOR_RESET "\n", ##__VA_ARGS__);\
    } while (0)
