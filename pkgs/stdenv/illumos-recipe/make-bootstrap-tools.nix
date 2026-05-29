# Build the bootstrap-tools tarball for x86_64-illumos.
#
# Usage:
#   nix-build pkgs/stdenv/illumos-recipe/make-bootstrap-tools.nix -A build
#
# Produces:
#   result/on-server/unpack.nar.xz          minimal unpacker (bash, xz, tar, mkdir)
#   result/on-server/bootstrap-tools.tar.xz frozen stdenv userland
#
# Tarballs are uploaded out-of-band; bootstrap-files/x86_64-illumos.nix
# references them by URL + sha256.
#
# Contract: NO /opt/local refs in the closure (audit step). /usr/* refs
# are expected — gcc-illumos's compiler driver binaries (xgcc, cc1,
# cc1plus, ...) carry /usr/gcc/10/lib/amd64 in RUNPATH inherited from
# the proto-strap host compiler that BUILT gcc-illumos. That resolves
# from the host illumos /usr/gcc/10, which is fine for a system-managed
# compiler runtime. Eliminating this requires self-hosted gcc-illumos
# (Phase 6 step 21); cosmetic until then.
#
# Not packaged: libc (system /lib/64 is used) and patchelf (illumos ELF
# is laid out differently; Sun ld emits clean RUNPATHs directly).
{
  pkgs ? import ../../.. { },
}:
let
  inherit (pkgs) runCommand closureInfo lib;
  inherit (pkgs.buildPackages) dumpnar;

  # gcc-illumos isn't wired into all-packages.nix yet; import directly.
  # Should match what pkgs/stdenv/illumos-recipe uses so the closures
  # union cleanly.
  gcc-illumos = import ../../development/compilers/gcc-illumos { };

  # gcc-illumos-scrubbed: gcc-illumos.out with proto-strap-hash,
  # original-gcc-illumos.out-hash, and /opt/local string references
  # byte-replaced to invalid bytes. This collapses the closure from
  # {scrubbed, gcc-illumos.out, gcc-illumos.lib, proto-strap} (which
  # leaked /opt/local via proto-strap's polluted binutils) down to
  # {scrubbed, gcc-illumos.lib}. gcc still works because the driver
  # uses its own binary's location to compute relative paths to its
  # libexec/include/lib subtrees (verified via `gcc -print-search-dirs`
  # + a hello-world compile-and-run).
  gcc-illumos-scrubbed = import ../../development/compilers/gcc-illumos-scrub { };

  # binutils-illumos pinned to the same store path strap-tools.nix uses.
  # Update both together when binutils gets rebuilt. This replaces the
  # original proto-strap dep, whose binutils carried /opt/local/lib in
  # DT_RUNPATH (pre-baked by SmartOS's pkgsrc-binutils build).
  binutils-illumos = builtins.storePath /nix/store/chjhxnwkp22s1nr2x9w8wdmmi1w9f0w7-binutils-2.44;

  # We don't use rsync here (it transitively wants cmake-minimal, which
  # tries to read stdenv.cc.bintools.bintools — null in nativeTools mode).
  # Plain `cp -a` + `chmod -R +w` is enough to flatten store paths.
  pack-all =
    packCmd: name: packages: fixups:
    (runCommand name
      {
        nativeBuildInputs = [
          dumpnar
        ];
      }
      ''
        base=$PWD
        requisites="$(cat ${closureInfo { rootPaths = packages; }}/store-paths)"

        for f in $requisites; do
          cp -aHR --no-preserve=mode "$f/." "$base/"
        done
        chmod -R +w "$base"
        cd $base

        rm -rf nix nix-support
        mkdir -p nix-support
        for dir in $requisites; do
          cd "$dir/nix-support" 2>/dev/null || continue
          for f in $(find . -type f); do
            mkdir -p "$base/nix-support/$(dirname $f)"
            cat $f >>"$base/nix-support/$f"
          done
        done
        rm -f $base/nix-support/propagated-build-inputs
        cd $base

        ${fixups}

        ${packCmd}
      ''
    );

  # Memory-conservative xz settings (illumos VM is RAM-bound during the
  # tarball pack step).
  nar-all = pack-all "dumpnar . | xz -6 -T 4 >$out";
  tar-all = pack-all "XZ_OPT=\"-6 -T 4\" tar cJf $out --hard-dereference --sort=name --numeric-owner --owner=0 --group=0 --mtime=@1 .";

  coreutils-big = pkgs.coreutils.override { singleBinary = false; };

  mkdir = runCommand "mkdir" { coreutils = coreutils-big; } ''
    mkdir -p $out/bin
    cp $coreutils/bin/mkdir $out/bin
  '';

in
rec {
  # Minimal unpacker shipped alongside bootstrap-tools.tar.xz.
  unpack =
    nar-all "unpack.nar.xz"
      (with pkgs; [
        bash
        mkdir
        xz
        gnutar
      ])
      ''
        rm -rf include lib/*.a lib/bash share
      '';

  # Main userland tarball. Toolchain (gcc-illumos + proto-strap binutils)
  # is packaged here so a fresh consumer doesn't need /opt/local at all.
  bootstrap-tools = tar-all "bootstrap-tools.tar.xz" (
    with pkgs;
    [
      # GNU userland
      coreutils-big
      bash
      gnutar
      findutils
      gnumake
      gnused
      gnugrep
      gawk
      diffutils
      patch

      # Compression
      xz
      xz.dev
      gzip
      bzip2
      bzip2.dev
      zlib
      zlib.dev

      # Toolchain — scrubbed gcc-illumos.out (proto-strap refs neutralized;
      # see comment on gcc-illumos-scrubbed above), original gcc-illumos.lib
      # (already clean; closure = self), plus binutils-illumos for gas /
      # GNU binutils (ld, ld.bfd, ld.gold, as, ar, nm, ...). Sun ld is the
      # system /usr/bin/ld, not packaged.
      gcc-illumos-scrubbed
      gcc-illumos.lib
      binutils-illumos

      # cc-wrapper helper
      expand-response-params
    ]
  ) ''
    # Trim non-essential docs to keep the tarball small.
    rm -rf share/info share/doc share/man
  '';

  build = runCommand "illumos-bootstrap-tools" { } ''
    mkdir -p $out/on-server
    ln -s ${unpack} $out/on-server/unpack.nar.xz
    ln -s ${bootstrap-tools} $out/on-server/bootstrap-tools.tar.xz
  '';
}
