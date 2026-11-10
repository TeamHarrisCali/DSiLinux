#!/usr/bin/env python3
"""Crop the melonDS top screen out of a full-desktop screenshot and enlarge it 4x.
Finds the largest near-black rectangle (the DS top screen showing the console).
Usage: topscreen.py in.png out.png"""
import sys
import numpy as np
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
a = np.asarray(im).astype(int)
dark = (a.sum(axis=2) < 40)
rows = dark.sum(axis=1)
cols = dark.sum(axis=0)
ys = np.where(rows > 150)[0]
# restrict to the contiguous band of dark rows that contains the most dark pixels
if len(ys) == 0:
    sys.exit("no dark region found")
# split into contiguous bands
bands, start = [], ys[0]
for p, q in zip(ys, ys[1:]):
    if q != p + 1:
        bands.append((start, p)); start = q
bands.append((start, ys[-1]))
y0, y1 = max(bands, key=lambda b: b[1] - b[0])
xs = np.where(dark[y0:y1 + 1].sum(axis=0) > (y1 - y0) * 0.5)[0]
x0, x1 = xs.min(), xs.max()
crop = im.crop((x0, y0, x1 + 1, y1 + 1))
crop = crop.resize((crop.width * 4, crop.height * 4), Image.NEAREST)
crop.save(sys.argv[2])
print(f"top screen {x0},{y0}-{x1},{y1}")
