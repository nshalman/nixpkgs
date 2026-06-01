# Stage-3 pin overlay — analogue of stage2-pin-overlay.nix, one
# stage up. Pins the stage-3-built userland (bash, coreutils,
# gcc-illumos, binutils, patchelf, ...) to the storePaths produced
# by the most recent successful full-chain rebuild.
#
# Purpose: protect the long-tail stage-3 outputs (gcc-illumos in
# particular, ~30 min compile) from cascading invalidation when we
# tweak stdenv-level tooling. With this overlay active, edits to
# downstream packages (or to a hypothetical stage 4 wrapper) only
# rebuild the affected leaves; stages 0-3 stay put.
#
# Usage:
#   nix-build -A stdenv \
#     --arg overlays '[ (import pkgs/stdenv/illumos-recipe/stage3-pin-overlay.nix {}) ]'
#
# Refresh: when stage 3 is rebuilt from source (e.g. after a clean
# rebuild that validates a portability fix), re-run the capture
# script in this file's commit message and update the paths below.

{ }:
let
  sp = builtins.storePath;

  mkPin = name: outs:
    let paths = builtins.mapAttrs (_: sp) outs; in
    paths
    // {
      type = "derivation";
      inherit name;
      outputs = builtins.attrNames outs;
      outPath = paths.out;
      drvPath = "/no-drv-pinned-${name}";
    };

  mkPin1 = name: out: mkPin name { inherit out; };
in
_self: _super: {
  bash               = mkPin1 "bash-interactive-5.3p3" /nix/store/cnjb9h4rcymp8g5vxp87zzg6cdq2sqgl-bash-interactive-5.3p3;
  bashNonInteractive = (mkPin1 "bash-5.3p3"            /nix/store/5aficjwagcz4ih4wa9sdxnmsnwgnyaqw-bash-5.3p3) // {
    shellPath = "/bin/bash";
  };
  coreutils          = mkPin1 "coreutils-9.8"          /nix/store/3k90rjkxdnr7nck7ky9jj4y6s210q9yi-coreutils-9.8;
  findutils          = mkPin1 "findutils-4.10.0"       /nix/store/3spd8188axllzs43gflj8z2icxg6f721-findutils-4.10.0;
  gnutar             = mkPin1 "gnutar-1.35"            /nix/store/i8r4744lr3y7k8fjm8hcvmz2fd01725f-gnutar-1.35;
  gnused             = mkPin1 "gnused-4.9"             /nix/store/ngx16fhgaqnsmb0xxypwysh8x5d5zg05-gnused-4.9;
  gnugrep            = mkPin1 "gnugrep-3.12"           /nix/store/3gs1hsday9mbw7mff793plhr5g2sah0n-gnugrep-3.12;
  gawk               = mkPin1 "gawk-5.3.2"             /nix/store/6m6w0p585r7m87qg7c3q7dp9bin9y3rq-gawk-5.3.2;
  gnumake            = mkPin1 "gnumake-4.4.1"          /nix/store/k5cz9imq2lh5rfs800bmcf3jab66a48z-gnumake-4.4.1;
  diffutils          = mkPin1 "diffutils-3.12"         /nix/store/5fr7hvvhmn545wjkbl45h7z971m6q89z-diffutils-3.12;
  patch              = mkPin1 "patch-2.8"              /nix/store/qc1g4kdb346p32p484kg9cykrbb9p3rw-patch-2.8;
  gzip               = mkPin1 "gzip-1.14"              /nix/store/53cbbmykmv1jyrrfbacz5jw4rminl6ys-gzip-1.14;
  patchelf           = mkPin1 "patchelf-0.15.2"        /nix/store/50f19gj83h6iihqaq1cyd9jw243kbr6c-patchelf-0.15.2;

  xz = mkPin "xz-5.8.3" {
    out = /nix/store/496mjmfqlzh2i8688sjj57vn122vr7a1-xz-5.8.3-bin;
    bin = /nix/store/496mjmfqlzh2i8688sjj57vn122vr7a1-xz-5.8.3-bin;
  };
  bzip2 = mkPin "bzip2-1.0.8" {
    out = /nix/store/qai4sl6vrghrhmann3839jnxw6igarhx-bzip2-1.0.8-bin;
    bin = /nix/store/qai4sl6vrghrhmann3839jnxw6igarhx-bzip2-1.0.8-bin;
  };

  binutils-unwrapped = mkPin "binutils-2.44" {
    out  = /nix/store/hwdl7wgsnm2ippxql0q9lcq44vz2qdgh-binutils-2.44;
    lib  = /nix/store/gf4xz4wh5p40k0vndri3lg1ga5jx7cz6-binutils-2.44-lib;
    dev  = /nix/store/lc14sa6zjszaxc224nw4fyd2sv6qd114-binutils-2.44-dev;
    info = /nix/store/11xnjzlfnscdqxn0dr6jyvam2pi8dzg3-binutils-2.44-info;
    man  = /nix/store/2j1bzbc771zcmglasrayilpgb47nwh4d-binutils-2.44-man;
  };

  gcc-illumos = mkPin "gcc-illumos-14.2.0-il-1" {
    out = /nix/store/hjrqsx8l32spnrnsfwx3a69nwkv6nzzx-gcc-illumos-14.2.0-il-1;
    lib = /nix/store/7qlj7ywjbfrfy120iz20k9crarnz2sh1-gcc-illumos-14.2.0-il-1-lib;
  };
}
