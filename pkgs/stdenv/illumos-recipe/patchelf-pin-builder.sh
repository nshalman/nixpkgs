set -e
export PATH=/usr/bin:/usr/sbin

mkdir -p $out/bin $out/nix-support

# Symlink the patchelf binary from the pinned upstream build.
ln -s $patchelfStorePath/bin/patchelf $out/bin/patchelf

# Re-emit the upstream patchelf setup-hook verbatim. Keeping a copy
# here (rather than ln -s'ing) means we don't depend on the upstream
# file layout, and the cascade fixupOutputHook gets registered the
# first time this derivation is in any package's nativeBuildInputs.
cat > $out/nix-support/setup-hook <<'HOOK'
fixupOutputHooks+=('if [ -z "${dontPatchELF-}" ]; then patchELF "$prefix"; fi')

patchELF() {
    local dir="$1"
    [ -e "$dir" ] || return 0

    echo "shrinking RPATHs of ELF executables and libraries in $dir"

    local i
    while IFS= read -r -d $'\0' i; do
        if [[ "$i" =~ .build-id ]]; then continue; fi
        if ! isELF "$i"; then continue; fi
        echo "shrinking $i"
        patchelf --shrink-rpath "$i" || true
    done < <(find "$dir" -type f -print0)
}
HOOK
