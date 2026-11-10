#!/bin/sh
# The ipwndev git mirror drops empty directories that the original SVN tree had.
# Recreate the ones the build needs (found by build failures; add more as they appear).
T="${1:-$(dirname "$0")/../work/dslinux}"
[ -f "$T/user/TinySDGL/lib" ] && rm -f "$T/user/TinySDGL/lib"   # stray file left by a failed build
mkdir -p "$T/user/TinySDGL/lib"

# Git checkout gives every file the same mtime, so make thinks autotools outputs are stale and
# tries to run aclocal/automake (not installed). Give generated files increasing timestamps,
# oldest first, in every directory that ships a generated configure.
find "$T/user" "$T/lib" -name configure -type f 2>/dev/null | while read -r c; do
  d=$(dirname "$c")
  n=0
  # sources oldest, then generated files in dependency order
  for f in configure.in configure.ac acinclude.m4 Makefile.am; do
    [ -e "$d/$f" ] && touch -d "2000-01-01 00:00:00" "$d/$f"
  done
  for f in aclocal.m4 configure config.h.in stamp-h.in Makefile.in; do
    [ -e "$d/$f" ] || continue
    n=$((n+1)); touch -d "2000-01-01 00:00:0$n" "$d/$f"
  done
  find "$d" -name Makefile.in -type f -exec touch -d "2000-01-01 00:00:09" {} +
done
