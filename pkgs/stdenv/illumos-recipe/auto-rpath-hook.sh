# illumos auto-rpath setup-hook
#
# gcc-illumos was configured with --with-ld=/usr/bin/ld per the SmartOS
# recipe, which bakes /usr/bin/ld into the compiled-in specs. gcc bypasses
# the wrapped ld in PATH and goes straight to Sun ld, so the auto-rpath-
# from-L logic in bintools-wrapper/ld-wrapper.sh never runs for gcc-driven
# links — buildInputs' libs get -L'd at link time but no matching -rpath
# ends up in the binary's DT_RUNPATH.
#
# Sun ld silently accepts `-rpath` as a synonym for `-R`. Mirror what
# bintoolsWrapper_addLDVars does, but emit `-rpath` (not just `-L`) for
# every store-path buildInput's lib directory. cc-wrapper then passes
# these via -Wl,-rpath, to Sun ld, which honors them.

illumosAutoRpath_addLDFlags() {
    if [[ -d "$1/lib" && "$1" == /nix/store/* ]]; then
        export NIX_LDFLAGS+=" -rpath $1/lib"
    fi
    if [[ -d "$1/lib64" && ! -L "$1/lib64" && "$1" == /nix/store/* ]]; then
        export NIX_LDFLAGS+=" -rpath $1/lib64"
    fi
}

addEnvHooks "$targetOffset" illumosAutoRpath_addLDFlags
