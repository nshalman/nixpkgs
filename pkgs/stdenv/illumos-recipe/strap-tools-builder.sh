set -eux

mkdir -p "$out/bin" "$out/lib"

# Compiler driver (gcc-illumos).
for tool in gcc g++ cpp gcov; do
    if [ -e "$gccIllumos/bin/$tool" ]; then
        ln -s "$gccIllumos/bin/$tool" "$out/bin/$tool"
    fi
done
ln -s "$gccIllumos/bin/gcc" "$out/bin/cc"

# Expose gcc-illumos's libgcc_s / libstdc++ so cc-wrapper's $out/lib
# resolves them.
for f in "$gccIllumos"/lib/amd64/*; do
    [ -e "$f" ] && ln -s "$f" "$out/lib/$(basename "$f")"
done

# GNU as + GNU binutils from proto-strap (g-prefixed → strip the g).
ln -s "$protoStrap/usr/gnu/bin/gas" "$out/bin/as"
for gtool in gaddr2line gar gc++filt gelfedit gld gnm gobjcopy gobjdump granlib greadelf gsize gstrings gstrip; do
    target="$protoStrap/usr/gnu/bin/$gtool"
    name="${gtool#g}"
    if [ -e "$target" ]; then
        ln -s "$target" "$out/bin/$name"
    fi
done
[ -e "$protoStrap/usr/gnu/bin/gld.bfd" ] && ln -s "$protoStrap/usr/gnu/bin/gld.bfd" "$out/bin/ld.bfd"

# pkgsrc (GNU-flavored) tools — taken FIRST so that GNU versions win over
# illumos /usr/bin SUS-flavored ones (illumos xargs has no -r, illumos
# sed has no -i, etc.). nixpkgs setup.sh assumes GNU semantics.
# Bring in everything pkgsrc ships, except things we already provide
# from the compiler/binutils above.
pkgsrc_skip=" gcc g++ cpp cc gcov as ar ld nm objcopy objdump ranlib strip readelf addr2line c++filt elfedit size strings ld.bfd "
for f in /opt/local/bin/*; do
    name="$(basename "$f")"
    case " $pkgsrc_skip " in
        *" $name "*) continue ;;
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
