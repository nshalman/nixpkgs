set -eux

mkdir -p "$out/bin" "$out/lib"

# proto-strap-cc: flat-layout view of the proto-strap compiler and GNU
# binutils, exactly what cc-wrapper / bintools-wrapper want under
# `$nativePrefix/bin/`. No /opt/local refs; no /usr/bin refs. Userland
# tools (bash, make, gawk, …) come from initialPath separately.

# Compiler driver (proto-strap's GCC 10.4.0).
for tool in gcc g++ cpp gcov; do
    if [ -e "$protoStrapPath/usr/gcc/10/bin/$tool" ]; then
        ln -s "$protoStrapPath/usr/gcc/10/bin/$tool" "$out/bin/$tool"
    fi
done
ln -s "$protoStrapPath/usr/gcc/10/bin/gcc" "$out/bin/cc"

# Expose proto-strap's libgcc_s / libstdc++ so cc-wrapper's $out/lib
# resolves them.
for f in "$protoStrapPath"/usr/gcc/10/lib/amd64/*; do
    [ -e "$f" ] && ln -s "$f" "$out/lib/$(basename "$f")"
done

# GNU as + GNU binutils from proto-strap (SmartOS strap-cache).
# proto-strap ships them under usr/gnu/bin/ with a `g` prefix
# (gas, gar, gld, gnm, ...). Strip the prefix when symlinking so
# cc-wrapper / bintools-wrapper see standard tool names.
#
# ld is the exception: we want Sun ld (illumos /usr/bin/ld) by
# default because gcc-illumos is configured --with-ld=/usr/bin/ld;
# gcc-driven links go straight to Sun ld regardless of what's in
# PATH. Mirroring that here keeps a single ld used everywhere AND
# keeps bintools-wrapper's auto-rpath logic working (Sun ld accepts
# -rpath as a synonym for -R). proto-strap's gld remains available
# as `ld.bfd` / `ld.gnu` for code that explicitly wants GNU ld.
for tool in addr2line ar as c++filt elfedit nm objcopy objdump ranlib readelf size strings strip; do
    target="$protoStrapPath/usr/gnu/bin/g$tool"
    if [ -e "$target" ]; then
        ln -s "$target" "$out/bin/$tool"
    fi
done
ln -s /usr/bin/ld "$out/bin/ld"
[ -e "$protoStrapPath/usr/gnu/bin/gld.bfd" ] && ln -s "$protoStrapPath/usr/gnu/bin/gld.bfd" "$out/bin/ld.bfd"
[ -e "$protoStrapPath/usr/gnu/bin/gld.bfd" ] && ln -s "$protoStrapPath/usr/gnu/bin/gld.bfd" "$out/bin/ld.gnu"

# Quick sanity print.
echo "=== proto-strap-cc assembled, total bin entries: ==="
ls "$out/bin" | wc -l
echo "=== libs ==="
ls "$out/lib" 2>/dev/null | wc -l
