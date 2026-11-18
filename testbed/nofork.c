/* testbed/tar_nommu_test.sh: as LD_PRELOAD, makes fork() fail with ENOSYS, as uClibc does on the DSi (no MMU) */
#include <errno.h>
#include <sys/types.h>
pid_t fork(void) { errno = ENOSYS; return -1; }   /* as uClibc without an MMU */
