/* testbed/terminfo_test.sh: asks the DSi's ncurses 5.4 (built natively) to read each compiled description: read_file_entry 1 and
 * setupterm 0 / err 1 mean nano on the DSi can use that terminal type (found 2026-11-18: the files were fine, the DSi build lacked USE_DATABASE) */
#include <stdio.h>
#include <curses.h>
#include <term.h>
int _nc_read_file_entry(const char *, TERMTYPE *);
int main(int argc, char **argv)
{
	int i, err, r;
	TERMTYPE tt;
	for (i = 2; i < argc; i++) {
		char path[512];
		snprintf(path, sizeof path, "%s/%c/%s", argv[1], argv[i][0], argv[i]);
		r = _nc_read_file_entry(path, &tt);
		printf("%-16s read_file_entry=%d  ", argv[i], r);
		err = 99;
		r = setupterm(argv[i], 1, &err);
		printf("setupterm=%d err=%d\n", r, err);
	}
	return 0;
}
