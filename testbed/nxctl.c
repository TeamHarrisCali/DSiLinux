/*
 * nxctl - drives the PC test bed's Nano-X server like a user and takes pictures of the screen.
 *   nxctl move X Y          pointer to (X, Y)
 *   nxctl click X Y         move there, press and release the left button
 *   nxctl down X Y / up X Y left button only
 *   nxctl rdown X Y / rmove X Y   right button held there (end with up X Y)
 *   nxctl key K             one key to the focused window: a character, or up down left right enter esc space pageup pagedown backspace
 *   nxctl shot FILE.ppm     the screen (read from the framebuffer file $FRAMEBUFFER, 256x192 RGB555) as a picture,
 *                           3x enlarged so it is easy to look at; nxctl shot1 FILE.ppm writes it 1:1
 *   nxctl wait MS           sleep
 * Several commands can follow each other on one command line.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "nano-X.h"

static int shot(const char *name, int scale)
{
	const char *fbname = getenv("FRAMEBUFFER");
	unsigned short px[256 * 192];
	FILE *f, *o;
	int x, y, sx, sy;

	f = fopen(fbname ? fbname : "/dev/shm/dsi-testbed-fb", "rb");
	if (!f || fread(px, 2, 256 * 192, f) != 256 * 192) {
		fprintf(stderr, "nxctl: cannot read the framebuffer file\n");
		return 1;
	}
	fclose(f);
	o = fopen(name, "wb");
	if (!o)
		return 1;
	fprintf(o, "P6\n%d %d\n255\n", 256 * scale, 192 * scale);
	for (y = 0; y < 192; y++)
		for (sy = 0; sy < scale; sy++)
			for (x = 0; x < 256; x++) {
				unsigned v = px[y * 256 + x];
				unsigned char rgb[3] = { ((v >> 10) & 31) << 3, ((v >> 5) & 31) << 3, (v & 31) << 3 };

				for (sx = 0; sx < scale; sx++)
					fwrite(rgb, 1, 3, o);
			}
	fclose(o);
	return 0;
}

static int keyval(const char *k)
{
	if (!strcmp(k, "up")) return MWKEY_UP;
	if (!strcmp(k, "down")) return MWKEY_DOWN;
	if (!strcmp(k, "left")) return MWKEY_LEFT;
	if (!strcmp(k, "right")) return MWKEY_RIGHT;
	if (!strcmp(k, "enter")) return MWKEY_ENTER;
	if (!strcmp(k, "esc")) return MWKEY_ESCAPE;
	if (!strcmp(k, "space")) return ' ';
	if (!strcmp(k, "pageup")) return MWKEY_PAGEUP;
	if (!strcmp(k, "pagedown")) return MWKEY_PAGEDOWN;
	if (!strcmp(k, "backspace")) return MWKEY_BACKSPACE;
	return (unsigned char)k[0];
}

int main(int argc, char **argv)
{
	int i = 1;

	if (GrOpen() < 0) {
		fprintf(stderr, "nxctl: no Nano-X server\n");
		return 1;
	}
	while (i < argc) {
		const char *c = argv[i++];

		if (!strcmp(c, "move") && i + 1 < argc) {
			GrInjectPointerEvent(atoi(argv[i]), atoi(argv[i + 1]), 0, 1);
			i += 2;
		} else if (!strcmp(c, "click") && i + 1 < argc) {
			int x = atoi(argv[i]), y = atoi(argv[i + 1]);

			GrInjectPointerEvent(x, y, 0, 1);
			GrFlush();
			usleep(50000);
			GrInjectPointerEvent(x, y, GR_BUTTON_L, 1);
			GrFlush();
			usleep(50000);
			GrInjectPointerEvent(x, y, 0, 1);
			i += 2;
		} else if ((!strcmp(c, "rdown") || !strcmp(c, "rmove")) && i + 1 < argc) {	/* right button (the DSi's L) held */
			GrInjectPointerEvent(atoi(argv[i]), atoi(argv[i + 1]), GR_BUTTON_R, 1);
			i += 2;
		} else if ((!strcmp(c, "down") || !strcmp(c, "up")) && i + 1 < argc) {
			GrInjectPointerEvent(atoi(argv[i]), atoi(argv[i + 1]), c[0] == 'd' ? GR_BUTTON_L : 0, 1);
			i += 2;
		} else if (!strcmp(c, "key") && i < argc) {
			int k = keyval(argv[i++]);

			GrInjectKeyboardEvent(0, k, 0, 0, 1);
			GrInjectKeyboardEvent(0, k, 0, 0, 0);
		} else if ((!strcmp(c, "shot") || !strcmp(c, "shot1")) && i < argc) {
			GrFlush();
			usleep(200000);		/* let the clients finish drawing */
			if (shot(argv[i++], c[4] ? 1 : 3))
				return 1;
		} else if (!strcmp(c, "wait") && i < argc) {
			GrFlush();
			usleep(atoi(argv[i++]) * 1000);
		} else {
			fprintf(stderr, "nxctl: what is '%s'?\n", c);
			return 1;
		}
		GrFlush();
	}
	GrClose();
	return 0;
}
