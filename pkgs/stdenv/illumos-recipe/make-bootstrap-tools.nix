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
# are expected — proto-strap and gcc-illumos carry /usr/gcc/10/lib/amd64
# in RUNPATH from their own build, and that resolves from the host
# illumos /usr/gcc/10 (which is fine; system-managed compiler runtime).
#
# Not packaged: libc (system /lib/64 is used) and patchelf (illumos ELF
# is laid out differently; Sun ld emits clean RUNPATHs directly).
{
  pkgs ? import ../../.. { },
}:
let
  inherit (pkgs) runCommand closureInfo lib;
  inherit (pkgs.buildPackages) dumpnar;

  # gcc-illumos and proto-strap aren't wired into all-packages.nix yet;
  # import directly. Both should match what pkgs/stdenv/illumos-recipe
  # uses so the closure unions cleanly.
  gcc-illumos = import ../../development/compilers/gcc-illumos { };
  proto-strap = import ../../development/compilers/proto-strap { };

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

      # Toolchain — both gcc-illumos outputs, plus proto-strap for
      # gas / GNU binutils. Sun ld is the system /usr/bin/ld, not packaged.
      gcc-illumos.out
      gcc-illumos.lib
      proto-strap

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
