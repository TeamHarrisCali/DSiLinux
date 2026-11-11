/*
 * doomgeneric_ds.c - doomgeneric (id Software's DOOM, GPL v2, ozkl/doomgeneric) on the DSLinuxDSi console.
 * Platform layer: the 320x200 picture (palette indices, built with -DCMAP256) is scaled to the 256x192 screen (4:3, which is what DOOM's
 * non square pixels were made for) and written straight into the screen memory on both pages, the buttons are read raw from /proc/dskeys
 * (game mode, see button.c), the clock is the screen refresh counter (59.8 Hz, no 10 ms steps).
 * Buttons: d-pad = move / turn, A = fire (and Enter in menus), B = use / open, L R = strafe, Y = run, X = next weapon (also "y" in the
 * quit question), Y = also "n", Start = menu (Esc), Select = automap (Tab), Start + Select together = leave at once.
 * No sound yet. Files: /home/doom/doom1.wad, /home/doom/default.cfg, saves in /home/doom/save.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <linux/fb.h>

#include "doomkeys.h"
#include "doomgeneric.h"
#include "i_video.h"

#define NDSFB_VSYNC	0x4e07
#define NDSFB_VBLCOUNT	0x4e0c

static int fbfd = -1, kfd = -1, fb_lb, fb_pages;
static unsigned char *fbmem;
static unsigned short pal15[256];
static unsigned short xmap[256], ymap[192];
static unsigned short *saved;			/* what the desktop looked like (page 0), put back when DOOM ends */
static long vbl0;

static void ds_restore(void)
{
	int pg, y;

	if (!fbmem || !saved)
		return;
	for (pg = 0; pg < fb_pages; pg++)
		for (y = 0; y < 192; y++)
			memcpy(fbmem + pg * 256 * fb_lb + y * fb_lb, saved + y * 256, 512);
}

void DG_Init(void)
{
	struct fb_fix_screeninfo fix;
	struct fb_var_screeninfo var;
	int i;

	fbfd = open("/dev/fb0", O_RDWR);
	if (fbfd < 0 || ioctl(fbfd, FBIOGET_FSCREENINFO, &fix) < 0 || ioctl(fbfd, FBIOGET_VSCREENINFO, &var) < 0) {
		fprintf(stderr, "dsdoom: cannot use /dev/fb0\n");
		exit(1);
	}
	fb_lb = fix.line_length;
	fb_pages = var.yres_virtual >= 512 ? 2 : 1;
	fbmem = mmap(NULL, fb_lb * (fb_pages == 2 ? 512 : var.yres_virtual), PROT_READ | PROT_WRITE, MAP_SHARED, fbfd, 0);
	if (fbmem == (unsigned char *)MAP_FAILED) {
		fprintf(stderr, "dsdoom: cannot map the screen\n");
		exit(1);
	}
	saved = malloc(256 * 192 * 2);
	if (saved) {
		int y;

		for (y = 0; y < 192; y++)
			memcpy(saved + y * 256, fbmem + y * fb_lb, 512);
	}
	atexit(ds_restore);
	kfd = open("/proc/dskeys", O_RDONLY);	/* game mode for as long as it is open */
	if (kfd < 0)
		fprintf(stderr, "dsdoom: no /proc/dskeys (%d): the desktop sees the buttons\n", errno);
	for (i = 0; i < 256; i++)
		xmap[i] = i * 5 / 4;			/* 256 -> 320 */
	for (i = 0; i < 192; i++)
		ymap[i] = i * 200 / 192;
	vbl0 = ioctl(fbfd, NDSFB_VBLCOUNT, 0);
}

static void make_palette(void)
{
	int i;

	for (i = 0; i < 256; i++)
		pal15[i] = 0x8000 | (colors[i].r >> 3) | ((colors[i].g >> 3) << 5) | ((colors[i].b >> 3) << 10);
	palette_changed = false;
}

void DG_DrawFrame(void)
{
	int y, x, pg;
	unsigned int line[128];			/* 256 pixels, two to a word */

	if (palette_changed)
		make_palette();
	for (y = 0; y < 192; y++) {
		const unsigned char *src = (const unsigned char *)DG_ScreenBuffer + ymap[y] * 320;

		for (x = 0; x < 128; x++)
			line[x] = pal15[src[xmap[2 * x]]] | ((unsigned int)pal15[src[xmap[2 * x + 1]]] << 16);
		for (pg = 0; pg < fb_pages; pg++) {
			volatile unsigned int *d = (volatile unsigned int *)(fbmem + pg * 256 * fb_lb + y * fb_lb);	/* VRAM: 16 or 32 bit writes */

			for (x = 0; x < 128; x++)
				d[x] = line[x];
		}
	}
}

void DG_SleepMs(uint32_t ms)
{
	usleep(ms * 1000);
}

uint32_t DG_GetTicksMs(void)
{
	unsigned long long v = ioctl(fbfd, NDSFB_VBLCOUNT, 0) - vbl0;

	return (uint32_t)(v * 16715ULL / 1000ULL);
}

/* ---- buttons: raw state -> press and release events ---- */
struct kev {
	int pressed;
	unsigned char key;
};
static struct kev queue[32];
static int qhead, qtail, polled, prev_raw, weapon;

static void push(int pressed, int key)
{
	int n = (qtail + 1) & 31;

	if (n != qhead) {
		queue[qtail].pressed = pressed;
		queue[qtail].key = (unsigned char)key;
		qtail = n;
	}
}

static const struct {
	int bit, key1, key2;
} keymap[] = {
	{ 0, KEY_FIRE, KEY_ENTER },		/* A */
	{ 1, KEY_USE, 0 },			/* B */
	{ 2, KEY_TAB, 0 },			/* Select */
	{ 3, KEY_ESCAPE, 0 },			/* Start */
	{ 4, KEY_RIGHTARROW, 0 },
	{ 5, KEY_LEFTARROW, 0 },
	{ 6, KEY_UPARROW, 0 },
	{ 7, KEY_DOWNARROW, 0 },
	{ 8, KEY_STRAFE_R, 0 },			/* R */
	{ 9, KEY_STRAFE_L, 0 },			/* L */
	{ 10, 'y', 0 },				/* X (weapon change is added below) */
	{ 11, KEY_RSHIFT, 'n' },		/* Y: run */
};

static void poll_buttons(void)
{
	char t[16];
	int n, raw = 0, i, changed;

	if (kfd >= 0) {
		lseek(kfd, 0, SEEK_SET);
		n = read(kfd, t, sizeof(t) - 1);
		if (n > 0) {
			t[n] = 0;
			raw = (int)strtol(t, NULL, 16);
		}
	}
	if ((raw & 0x0c) == 0x0c)		/* Start + Select: leave */
		exit(0);
	changed = raw ^ prev_raw;
	for (i = 0; i < (int)(sizeof(keymap) / sizeof(keymap[0])); i++) {
		if (!(changed & (1 << keymap[i].bit)))
			continue;
		push((raw >> keymap[i].bit) & 1, keymap[i].key1);
		if (keymap[i].key2)
			push((raw >> keymap[i].bit) & 1, keymap[i].key2);
	}
	if ((changed & 0x400) && (raw & 0x400)) {	/* X: try the next weapon number (a weapon you do not have is ignored) */
		weapon = weapon % 7 + 1;
		push(1, '0' + weapon);
		push(0, '0' + weapon);
	}
	prev_raw = raw;
}

int DG_GetKey(int *pressed, unsigned char *key)
{
	if (qhead == qtail && !polled) {
		poll_buttons();
		polled = 1;
	}
	if (qhead == qtail) {
		polled = 0;
		return 0;
	}
	*pressed = queue[qhead].pressed;
	*key = queue[qhead].key;
	qhead = (qhead + 1) & 31;
	return 1;
}

void DG_SetWindowTitle(const char *title)
{
}

int main(int argc, char **argv)
{
	static char *defargv[] = { "dsdoom", "-iwad", "/home/doom/doom1.wad", "-config", "/home/doom/default.cfg", "-savedir", "/home/doom/save",
				   "-nosound", "-nomusic", "-mb", "5", NULL };

	mkdir("/home/doom/save", 0755);
	if (argc <= 1) {
		argc = (int)(sizeof(defargv) / sizeof(defargv[0])) - 1;
		argv = defargv;
	}
	doomgeneric_Create(argc, argv);
	for (;;)
		doomgeneric_Tick();
	return 0;
}
