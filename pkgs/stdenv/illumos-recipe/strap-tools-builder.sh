set -eux

mkdir -p "$out/bin" "$out/lib"

# Compiler driver (gcc-illumos).
for tool in gcc g++ cpp gcov; do
    if [ -e "$gccIllumosOut/bin/$tool" ]; then
        ln -s "$gccIllumosOut/bin/$tool" "$out/bin/$tool"
    fi
done
ln -s "$gccIllumosOut/bin/gcc" "$out/bin/cc"

# Expose gcc-illumos's libgcc_s / libstdc++ so cc-wrapper's $out/lib
# resolves them. Libs live in the `lib` output (separate from compiler).
for f in "$gccIllumosLib"/lib/amd64/*; do
    [ -e "$f" ] && ln -s "$f" "$out/lib/$(basename "$f")"
done

# GNU as + GNU binutils from proto-strap (SmartOS strap-cache).
# proto-strap ships them under usr/gnu/bin/ with a `g` prefix
# (gas, gar, gld, gnm, ...). Strip the prefix when symlinking so
# wrappers see standard tool names.
#
# ld is the exception: we want Sun ld (illumos /usr/bin/ld) by
# default because gcc-illumos was configured --with-ld=/usr/bin/ld;
# gcc-driven links go straight to Sun ld regardless of what's in
# PATH, so making strap-tools/bin/ld also point at Sun ld keeps a
# single ld used everywhere AND keeps the bintools-wrapper
# auto-rpath logic working (Sun ld accepts -rpath as a synonym for
# -R). proto-strap's gld remains available as `ld.bfd` / `ld.gnu`
# for code that explicitly wants GNU ld.
#
# Caveat: proto-strap's binutils were built by SmartOS's pkgsrc and
# carry /opt/local/lib in DT_RUNPATH. Stage 0/1 outputs that link
# via these tools inherit the reference. Stage 2 builds binutils
# fresh and stage 3 drops strap-tools entirely; stage 3+ closures
# are clean.
for tool in addr2line ar as c++filt elfedit nm objcopy objdump ranlib readelf size strings strip; do
    target="$protoStrapPath/usr/gnu/bin/g$tool"
    if [ -e "$target" ]; then
        ln -s "$target" "$out/bin/$tool"
    fi
done
ln -s /usr/bin/ld "$out/bin/ld"
[ -e "$protoStrapPath/usr/gnu/bin/gld.bfd" ] && ln -s "$protoStrapPath/usr/gnu/bin/gld.bfd" "$out/bin/ld.bfd"
[ -e "$protoStrapPath/usr/gnu/bin/gld.bfd" ] && ln -s "$protoStrapPath/usr/gnu/bin/gld.bfd" "$out/bin/ld.gnu"

# pkgsrc (GNU-flavored) tools — taken FIRST so that GNU versions win over
# illumos /usr/bin SUS-flavored ones (illumos xargs has no -r, illumos
# sed has no -i, etc.). nixpkgs setup.sh assumes GNU semantics.
# Bring in everything pkgsrc ships, except things we already provide
# from the compiler/binutils above, and except *-config helpers (which
# emit -L/opt/local/lib -Wl,-R/opt/local/lib that contaminate everything
# downstream — observed in gnugrep + binutils RUNPATH).
pkgsrc_skip=" gcc g++ cpp cc gcov as ar ld nm objcopy objdump ranlib strip readelf addr2line c++filt elfedit size strings ld.bfd pkg-config "
for f in /opt/local/bin/*; do
    name="$(basename "$f")"
    case " $pkgsrc_skip " in
        *" $name "*) continue ;;
    esac
    case "$name" in
        *-config) continue ;;
    esac
    [ -e "$out/bin/$name" ] && continue
    ln -s "$f" "$out/bin/$name"
done

# g-prefixed pkgsrc tools mapped to plain names (where pkgsrc didn't
# already provide a plain symlink).
for g in /opt/local/bin/g*; do
    plain="$(basename "$g")"
    plain="${plain#g}"
    [ -z "$plain" ] && continue
    case " $pkgsrc_skip " in *" $plain "*) continue ;; esac
    case "$plain" in *-config) continue ;; esac
    [ -e "$out/bin/$plain" ] && continue
    [ -x "$g" ] && ln -s "$g" "$out/bin/$plain"
done

# illumos /usr/bin — fills holes pkgsrc doesn't cover. Skip bash (4.3,
# too old) and tools we already provide (compiler, binutils, GNU
# tools above).
host_skip=" bash make ar as ld nm objcopy objdump ranlib strip readelf addr2line c++filt elfedit size strings gcc g++ cpp cc gcov "
for f in /usr/bin/*; do
    name="$(basename "$f")"
    case " $host_skip " in
        *" $name "*) continue ;;
    esac
    [ -e "$out/bin/$name" ] && continue
    ln -s "$f" "$out/bin/$name"
done

# `make` → gmake (illumos /usr/bin/make is dmake / SunPro make, not GNU).
[ -e "$out/bin/gmake" ] && [ ! -e "$out/bin/make" ] && ln -s "$out/bin/gmake" "$out/bin/make"

# Quick sanity print.
echo "=== strap-tools assembled, total bin entries: ==="
ls "$out/bin" | wc -l
echo "=== libs ==="
ls "$out/lib" 2>/dev/null | wc -l
