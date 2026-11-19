#!/usr/bin/env python3
"""
The touch screen's keyboard art in the desktop's Windows 95 look (2026-11-19, docs/TOUCHSCREEN-PLAN.md): grey keys with the
white / light / dark / black bevel of the desktop's buttons, black legends, a pressed (sunken) version, lower and upper case, and the
Caps Lock light (palette index 5, which the driver turns green or dark). The key positions come from qwertyKeyMap in keyboard.map.c,
which this does not change: every key keeps its tiles, so touching works exactly as before.

Writes, in work/dslinux/linux-2.6.x/drivers/input/touchscreen:
  keyboard.raw.c   the tiles (4 bits per pixel), their length, and the four 32x15 maps (bg: unpressed / pressed; fg: lower / upper)
  master.pal.c     the 16 colours of palette 0
and, with --preview FILE.png, a picture of the four combinations to check by eye.
Fonts: the kernel's own console fonts (font_8x8.c for single characters, font_mini_4x6.c for labels like "Shift").
Usage: scripts/make-keyboard-art.py [--preview out.png]
"""
import os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'work', 'dslinux', 'linux-2.6.x')
TS = os.path.join(ROOT, 'drivers', 'input', 'touchscreen')
FONTS = os.path.join(ROOT, 'drivers', 'video', 'console')

# palette 0 (RGB555, red in the low bits). Index 0 is transparent; 5 is the Caps light (the driver rewrites it); 6 fills tile 0,
# which the trackpad shows through palette 1 (its own colour there)
FACE, BLACK, WHITE, LIGHT, DARK, LED, SOLID = 4, 1, 2, 3, 7, 5, 6
PAL = [0x6318, 0x0000, 0x7fff, 0x6f7b, 0x6318, 0x0060, 0x6318, 0x4210] + [0x0000] * 8

ROW0, ROWS, COLS = 9, 15, 32		# the keyboard: tile rows 9..23

def hexbytes(path, name):
	s = open(path, encoding='latin-1').read()
	s = s[s.index(name):]
	s = s[s.index('{') + 1:s.index('};')]
	s = re.sub(r'/\*.*?\*/', '', s, flags=re.S)
	return [int(t, 16) for t in re.findall(r'0x[0-9a-fA-F]+', s)]

F8 = hexbytes(os.path.join(FONTS, 'font_8x8.c'), 'fontdata_8x8')		# 8 bytes per character, bit 7 = left
F4 = hexbytes(os.path.join(FONTS, 'font_mini_4x6.c'), 'fontdata_mini_4x6')	# 6 bytes per character, high nibble

def glyph8(ch):
	rows = F8[ord(ch) * 8:ord(ch) * 8 + 8]
	px = [(x, y) for y in range(8) for x in range(8) if rows[y] & (0x80 >> x)]
	if not px:
		return [], 0, 0
	x0 = min(p[0] for p in px); x1 = max(p[0] for p in px); y0 = min(p[1] for p in px); y1 = max(p[1] for p in px)
	return [(x - x0, y - y0) for x, y in px], x1 - x0 + 1, y1 - y0 + 1

def text4(s):
	px, x = [], 0
	for ch in s:
		rows = F4[ord(ch) * 6:ord(ch) * 6 + 6]
		for y in range(6):
			for gx in range(4):
				if rows[y] & (0x80 >> gx):
					px.append((x + gx, y))
		x += 4
	if not px:
		return [], 0, 0
	w = max(p[0] for p in px) + 1
	return px, w, 6

def keymap():
	s = open(os.path.join(TS, 'keyboard.map.c')).read()
	s = s[s.index('qwertyKeyMap'):]
	s = s[s.index('{') + 1:s.index('};')]
	toks = [t.strip() for t in s.replace('\n', ' ').split(',') if t.strip()]
	assert len(toks) == 32 * 24, len(toks)
	return [toks[(ROW0 + r) * 32:(ROW0 + r + 1) * 32] for r in range(ROWS)]

SHIFTED = dict(zip('1234567890', '!@#$%^&*()'))
SYMBOLS = {'GRAVE': ('`', '~'), 'MINUS': ('-', '_'), 'EQUAL': ('=', '+'), 'LEFTBRACE': ('[', '{'), 'RIGHTBRACE': (']', '}'),
	   'BACKSLASH': ('\\', '|'), 'SEMICOLON': (';', ':'), 'APOSTROPHE': ("'", '"'), 'COMMA': (',', '<'), 'DOT': ('.', '>'),
	   'SLASH': ('/', '?'), '102ND': ('<', '>')}
WORDS = {'ESC': 'Esc', 'BACKSPACE': 'Bksp', 'TAB': 'Tab', 'CAPSLOCK': 'Caps', 'ENTER': 'Enter', 'LEFTSHIFT': 'Shift',
	 'RIGHTSHIFT': 'Shift', 'LEFTCTRL': 'Ctrl', 'RIGHTCTRL': 'Ctrl', 'LEFTALT': 'Alt', 'RIGHTALT': 'Alt', 'LEFTMETA': 'Win',
	 'RIGHTMETA': 'Win', 'MENU': 'Menu', 'SPACE': ''}

def legend(name, upper):
	k = name[4:]
	if len(k) == 1 and k.isalpha():
		return ('c', k if upper else k.lower())
	if len(k) == 1 and k.isdigit():
		return ('c', SHIFTED[k] if upper else k)
	if k in SYMBOLS:
		return ('c', SYMBOLS[k][1 if upper else 0])
	if re.match(r'F\d+$', k):
		return ('w', k)
	return ('w', WORDS.get(k, k[:4].title()))

def components(km):
	seen, comps = set(), []
	for r in range(ROWS):
		for c in range(COLS):
			if km[r][c] == 'KEY_RESERVED' or (r, c) in seen:
				continue
			name, stack, tiles = km[r][c], [(r, c)], []
			seen.add((r, c))
			while stack:
				y, x = stack.pop()
				tiles.append((y, x))
				for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
					ny, nx = y + dy, x + dx
					if 0 <= ny < ROWS and 0 <= nx < COLS and (ny, nx) not in seen and km[ny][nx] == name:
						seen.add((ny, nx))
						stack.append((ny, nx))
			comps.append((name, tiles))
	return comps

def draw():
	W, H = COLS * 8, ROWS * 8
	bg = {p: [[FACE] * W for _ in range(H)] for p in (0, 1)}		# 0 unpressed, 1 pressed
	fg = {u: [[0] * W for _ in range(H)] for u in (0, 1)}		# 0 lower, 1 upper
	for name, tiles in components(keymap()):
		P = set((x, y) for (r, c) in tiles for y in range(r * 8, r * 8 + 8) for x in range(c * 8, c * 8 + 8))

		def out(x, y):
			return (x, y) not in P

		for (x, y) in P:
			# depth: how many pixels from the key's edge (1 = the gap between keys)
			d = min(k for k in range(1, 9) if any(out(x + dx * k, y + dy * k) for dx in (-1, 0, 1) for dy in (-1, 0, 1)) or k == 8)
			if d == 1:
				col = (FACE, FACE)
			elif d in (2, 3):
				br = any(out(x + k, y) or out(x, y + k) or out(x + k, y + k) for k in range(1, d + 1))
				if d == 2:	# outer bevel: raised white / black, pressed black / white
					col = (BLACK, WHITE) if br else (WHITE, BLACK)
				else:		# inner bevel: raised light / dark, pressed dark / light
					col = (DARK, LIGHT) if br else (LIGHT, DARK)
			else:
				col = (FACE, FACE)
			bg[0][y][x], bg[1][y][x] = col
		# the legend, centred on the key's top row (the Enter key is an L: its label goes in the wide part)
		r0 = min(r for r, c in tiles)
		top = [(r, c) for r, c in tiles if r == r0]
		bx0 = min(c for r, c in top) * 8; bx1 = (max(c for r, c in top) + 1) * 8
		by0 = r0 * 8; by1 = by0 + 16		# every key row is two tiles tall
		if name == 'KEY_CAPSLOCK':	# the Caps light: a small bar in the corner, colour 5
			for yy in range(by0 + 4, by0 + 6):
				for xx in range(bx1 - 8, bx1 - 4):
					bg[0][yy][xx] = bg[1][yy][xx] = LED
		for u in (0, 1):
			kind, s = legend(name, u)
			if kind == 'c':
				px, w, h = glyph8(s)
			else:
				px, w, h = text4(s)
			ox = bx0 + (bx1 - bx0 - w) // 2
			oy = by0 + (by1 - by0 - h) // 2
			for x, y in px:
				fg[u][oy + y][ox + x] = BLACK
	return bg, fg

def tiles_of(canvas):
	return [tuple(canvas[r * 8 + y][c * 8 + x] for y in range(8) for x in range(8)) for r in range(ROWS) for c in range(COLS)]

def main():
	bg, fg = draw()
	solid = tuple([SOLID] * 64)
	clear = tuple([0] * 64)
	tl, idx = [solid, clear], {solid: 0, clear: 1}		# tile 0 solid (the trackpad uses it), tile 1 transparent

	def tid(t):
		if t not in idx:
			idx[t] = len(tl)
			tl.append(t)
		return idx[t]

	maps = {}
	for key, canvas in (('Unpressed', bg[0]), ('Pressed', bg[1]), ('Qwerty_Lower', fg[0]), ('Qwerty_Upper', fg[1])):
		maps[key] = [tid(t) for t in tiles_of(canvas)]
	n = len(tl)
	data = []
	for t in tl:
		for y in range(8):
			for x in range(0, 8, 2):
				data.append(t[y * 8 + x] | (t[y * 8 + x + 1] << 4))
	out = ['/*', ' * The touch keyboard in the Windows 95 look: generated by scripts/make-keyboard-art.py (do not edit by hand).',
	       ' * %d tiles; maps are 32 x 15 tile numbers (palette 0) for tile rows 9..23.' % n, ' */',
	       'const unsigned int keyboard_TilesLen = %d;' % len(data),
	       'const unsigned char keyboard_Tiles[%d] = {' % len(data)]
	for i in range(0, len(data), 16):
		out.append('\t' + ', '.join('0x%02x' % b for b in data[i:i + 16]) + ',')
	out.append('};')
	for key in ('Unpressed', 'Pressed', 'Qwerty_Lower', 'Qwerty_Upper'):
		out.append('const unsigned short keyboard_Map_%s[480] = {' % key)
		m = maps[key]
		for i in range(0, 480, 16):
			out.append('\t' + ', '.join('0x%04x' % v for v in m[i:i + 16]) + ',')
		out.append('};')
	open(os.path.join(TS, 'keyboard.raw.c'), 'w').write('\n'.join(out) + '\n')
	open(os.path.join(TS, 'master.pal.c'), 'w').write(
		'/* palette 0 of the touch screen: scripts/make-keyboard-art.py (5 = the Caps light, set by the driver) */\n'
		'const unsigned short master_Palette[16] = {\n\t' + ', '.join('0x%04x' % c for c in PAL) + '\n};\n')
	print('%d tiles (%d bytes)' % (n, len(data)))
	if '--preview' in sys.argv:
		from PIL import Image
		rgb = [((c & 31) * 255 // 31, ((c >> 5) & 31) * 255 // 31, ((c >> 10) & 31) * 255 // 31) for c in PAL]
		img = Image.new('RGB', (COLS * 8, ROWS * 8 * 2 + 4), (255, 255, 255))
		for k, (b, f) in enumerate(((bg[0], fg[0]), (bg[1], fg[1]))):
			for y in range(ROWS * 8):
				for x in range(COLS * 8):
					c = f[y][x] or b[y][x]
					img.putpixel((x, y + k * (ROWS * 8 + 4)), rgb[c])
		p = sys.argv[sys.argv.index('--preview') + 1]
		img.resize((img.width * 3, img.height * 3), Image.NEAREST).save(p)
		print('preview:', p)

main()
