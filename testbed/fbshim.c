/*
 * fbshim.c - LD_PRELOAD for the PC test bed: the Nano-X server's framebuffer driver (scr_fb.c) opens $FRAMEBUFFER, which is a plain
 * 98304 byte file here, and asks it for its geometry with framebuffer ioctls. This answers them like the DS top screen does
 * (256x192, 16 bit, one page), so the server draws into the file and testbed/nxctl can turn it into a picture.
 * Everything else goes to the real ioctl().
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdarg.h>
#include <string.h>
#include <linux/fb.h>
#include <sys/ioctl.h>

int ioctl(int fd, unsigned long req, ...)
{
	static int (*real)(int, unsigned long, ...);
	va_list ap;
	void *arg;

	va_start(ap, req);
	arg = va_arg(ap, void *);
	va_end(ap);
	if (!real)
		real = (int (*)(int, unsigned long, ...))dlsym(RTLD_NEXT, "ioctl");
	if (req == FBIOGET_FSCREENINFO) {
		struct fb_fix_screeninfo *f = arg;

		memset(f, 0, sizeof(*f));
		strcpy(f->id, "dsi-testbed");
		f->smem_len = 256 * 192 * 2;
		f->type = FB_TYPE_PACKED_PIXELS;
		f->visual = FB_VISUAL_TRUECOLOR;
		f->line_length = 512;
		return 0;
	}
	if (req == FBIOGET_VSCREENINFO) {
		struct fb_var_screeninfo *v = arg;

		memset(v, 0, sizeof(*v));
		v->xres = v->xres_virtual = 256;
		v->yres = v->yres_virtual = 192;
		v->bits_per_pixel = 16;
		v->red.offset = 10;	v->red.length = 5;
		v->green.offset = 5;	v->green.length = 5;
		v->blue.offset = 0;	v->blue.length = 5;
		return 0;
	}
	if ((req & 0xff00) == 0x4600 || (req & 0xff00) == 0x4e00)	/* other framebuffer and DSLinux ioctls: accept and ignore */
		return 0;
	return real(fd, req, arg);
}
