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
    [[ "$1" == /nix/store/* ]] || return 0
    # Only add an rpath if the buildInput actually ships shared libraries.
    # Without this check, -dev outputs (which contain only headers /
    # pkg-config files under lib/) land in every binary's RUNPATH and
    # pull their full closure (including bash via patched shebangs in
    # `lib-config` scripts → strap-tools → proto-strap → gcc-illumos.out)
    # into downstream runtime deps. Mirror bintoolsWrapper_addLDVars'
    # `lib/lib*` glob check.
    local -a glob
    if [[ -d "$1/lib" ]]; then
        glob=( "$1"/lib/lib* )
        if (( ${#glob[@]} > 0 )); then
            export NIX_LDFLAGS+=" -rpath $1/lib"
        fi
    fi
    if [[ -d "$1/lib64" && ! -L "$1/lib64" ]]; then
        glob=( "$1"/lib64/lib* )
        if (( ${#glob[@]} > 0 )); then
            export NIX_LDFLAGS+=" -rpath $1/lib64"
        fi
    fi
}

addEnvHooks "$targetOffset" illumosAutoRpath_addLDFlags
