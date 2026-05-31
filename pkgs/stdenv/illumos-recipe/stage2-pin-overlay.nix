# Stage-2 pin overlay for fast stage-3 iteration.
#
# When applied as an `overlays` entry, this replaces the
# stage-2-built userland (bash, coreutils, gcc-illumos, binutils,
# patchelf, ...) with `builtins.storePath` references to a previously-
# built consistent set. The result: editing any package's nix
# expression does NOT trigger a stage-1/2 rebuild — only stage 3's
# wrap-cc / wrap-bintools step has to redo work. This collapses an
# iteration loop from hours to ~minutes.
#
# How the paths were captured: rewind to a commit where
# `nix-build -A stdenv --dry-run` reports nothing to build (i.e.
# stage 2 is fully realised in /nix/store), then extract
# `pkgs.stdenv.initialPath`, `pkgs.stdenv.cc.cc.{out,lib}`,
# `pkgs.stdenv.cc.bintools.bintools.{out,lib,dev,info,man}`, and
# `pkgs.patchelf`. The pin is intentionally one-shot — when stage 3
# builds clean with this overlay active, drop the overlay and trigger
# one full chain rebuild from source to confirm the production
# closure matches.
#
# Usage:
#   nix-build -A stdenv \
#     --arg overlays '[ (import pkgs/stdenv/illumos-recipe/stage2-pin-overlay.nix {}) ]'

{ }:
let
  sp = builtins.storePath;

  # Mimic a multi-output derivation enough for nixpkgs consumers.
  # The shape exposes:
  #   - outPath / `${pin}` interpolates to the main (`out`) store path
  #   - .out, .lib, .dev, ... each interpolate to their own store path
  #   - `type = "derivation"` so isDerivation / lib.getOutput accept it
  # We deliberately do NOT set a real drvPath — no derivation is
  # registered or built; nix sees the storePaths as valid roots.
  mkPin = name: outs:
    let paths = builtins.mapAttrs (_: sp) outs; in
    paths
    // {
      type = "derivation";
      inherit name;
      outputs = builtins.attrNames outs;
      outPath = paths.out;
      # Placeholder; never read because we never build this "drv".
      drvPath = "/no-drv-pinned-${name}";
    };

  # Shorthand for single-output packages.
  mkPin1 = name: out: mkPin name { inherit out; };
in
_self: _super: {
  # Single-output userland.
  bash               = mkPin1 "bash-interactive-5.3p3" /nix/store/w8sslzg145w27arh7kjw42ifwm3sidbf-bash-interactive-5.3p3;
  bashNonInteractive = (mkPin1 "bash-5.3p3"            /nix/store/wi01jir93az2jvm9b86nia4gyycgv24s-bash-5.3p3) // {
    # Needed by allPackages.nix `runtimeShell = "${pkg}${pkg.shellPath}"`.
    shellPath = "/bin/bash";
  };
  coreutils          = mkPin1 "coreutils-9.8"          /nix/store/dhhphym77m4bvn2wrali85mby4pyaq31-coreutils-9.8;
  findutils          = mkPin1 "findutils-4.10.0"       /nix/store/3dyqs67fg30iym5qwmqpq0vdqvnsa9vz-findutils-4.10.0;
  gnutar             = mkPin1 "gnutar-1.35"            /nix/store/ljw5nrg2gbnk1xw5biahm899b99yrgkn-gnutar-1.35;
  gnused             = mkPin1 "gnused-4.9"             /nix/store/6kd0mzrhljkcm53m8vxkmasixm7bgifq-gnused-4.9;
  gnugrep            = mkPin1 "gnugrep-3.12"           /nix/store/6nd2sphsampy1ln0qb8yd4bws2k1wzxi-gnugrep-3.12;
  gawk               = mkPin1 "gawk-5.3.2"             /nix/store/yfk8ljz2jivm19a93wdwiqij6fs3x9m9-gawk-5.3.2;
  gnumake            = mkPin1 "gnumake-4.4.1"          /nix/store/36sy3p5zgw3wggdjjnhjxyqr981pc82m-gnumake-4.4.1;
  diffutils          = mkPin1 "diffutils-3.12"         /nix/store/lq86qfccx1gjk5r2x8wqaprzqhcikg20-diffutils-3.12;
  patch              = mkPin1 "patch-2.8"              /nix/store/cny7v2xcqnplx9x6479d44japm7ag4y8-patch-2.8;
  gzip               = mkPin1 "gzip-1.14"              /nix/store/925ivzfhp0qmyjmqb8kvsz5bszfr1q99-gzip-1.14;
  patchelf           = mkPin1 "patchelf-0.15.2"        /nix/store/gnq96hmw015jcnd4bl9k93pq5sw5hqfr-patchelf-0.15.2;

  # xz and bzip2: their initialPath entry is the -bin output. Pin
  # both .out (= bin) and .bin so either access pattern resolves.
  xz = mkPin "xz-5.8.3" {
    out = /nix/store/qfxy32r5716qskk73prjcpcf3iqwwd15-xz-5.8.3-bin;
    bin = /nix/store/qfxy32r5716qskk73prjcpcf3iqwwd15-xz-5.8.3-bin;
  };
  bzip2 = mkPin "bzip2-1.0.8" {
    out = /nix/store/460awn11hk83bymj0k67180czill112x-bzip2-1.0.8-bin;
    bin = /nix/store/460awn11hk83bymj0k67180czill112x-bzip2-1.0.8-bin;
  };

  # binutils-unwrapped is consumed by stage 3's wrapBintoolsWith as
  # a multi-output drv (out/lib/dev/info/man).
  binutils-unwrapped = mkPin "binutils-2.44" {
    out  = /nix/store/bb8f7wcdh50xcjv8akx0hd1v4j5yzvk9-binutils-2.44;
    lib  = /nix/store/r1asdj561m6b2xiyfg56qaizpkgxgli3-binutils-2.44-lib;
    dev  = /nix/store/b98l77izxi7iab5zabs0azms88s5nvkk-binutils-2.44-dev;
    info = /nix/store/3i8f1r9h1racrwwzh1593q7gn2h47zhp-binutils-2.44-info;
    man  = /nix/store/d4345wrk3g277w6mdfs7470x40lxwzx0-binutils-2.44-man;
  };

  # gcc-illumos: stage 3's cleanCC wraps THIS gcc-illumos. The pin
  # lets us skip the long compiler rebuild entirely during iteration.
  gcc-illumos = mkPin "gcc-illumos-14.2.0-il-1" {
    out = /nix/store/bzvb3ps82ha7aynf3l38ax77m6q257n3-gcc-illumos-scrubbed;
    lib = /nix/store/8gqqj837r7pqhcbg6lchna8fjy0g5vz3-gcc-illumos-14.2.0-il-1-lib;
  };
}
