# gcc-illumos-scrub: produces a gcc-illumos.out variant with proto-strap
# byte references neutralized so consumers do not transitively pull
# proto-strap into their closures.
#
# Why this exists
# ---------------
# gcc-illumos is built using proto-strap (SmartOS's GCC 10 strap) as
# the host compiler. gcc-illumos's configure embeds proto-strap paths
# in 9 distinct strings across the compiler driver binaries:
#   1 × compiled-in configure command line (contains --with-as=...)
#   5 × C++ libstdc++ header search paths (host gcc-10's libstdc++)
#   3 × include-fixed paths from gcc-10's fixincludes pass
#
# These end up in cc1plus, lto1, the gcc/g++ drivers, etc. as plain
# strings. nix's store-path scanner finds them and pulls proto-strap
# into the closure of anything that consumes gcc-illumos.out.
# proto-strap's binutils (in /usr/gnu/bin) carry /opt/local/lib in
# DT_RUNPATH (pre-baked by SmartOS's pkgsrc-binutils build), which
# fails the hermeticity audit for any tarball that includes them.
#
# The scrub
# ---------
# Byte-replace the 32-char proto-strap hash in every file containing
# proto-strap-hash refs with an invalid nix32 hash (replace the
# leading char with 'e', which is excluded from nix's store-path
# alphabet). nix's scanner no longer recognizes the path as a store
# reference; proto-strap drops from the closure. The bytes still
# exist in cc1plus as garbage paths to nonexistent store entries;
# cc1plus stat()s them at compile-time, gets ENOENT, falls through to
# its other search paths. Functional impact: none for ordinary
# compilation.
#
# gcc-illumos.lib is already clean (no proto-strap refs in any ELF,
# closure = self), so we touch only .out. Scrubbed.out's RUNPATH
# continues to point at the unchanged gcc-illumos.lib.
{
  gccIllumos ? import ../gcc-illumos { },
  protoStrap ? import ../proto-strap { },
  # Default to package-set tools so the scrub uses nix-built python +
  # GNU grep rather than the host's pkgsrc copies. illumos /usr/bin/grep
  # is SUSv2-only and doesn't accept -a (treat-binary-as-text), so the
  # builder needs GNU grep on PATH.
  pkgs ? import ../../../.. { },
  python3 ? pkgs.python3,
  gnugrep ? pkgs.gnugrep,
  system ? "x86_64-illumos",
}:
derivation {
  name = "gcc-illumos-scrubbed";
  inherit system;

  origOut = gccIllumos.out;
  protoStrapPath = "${protoStrap}";
  python3Path = "${python3}";
  gnugrepPath = "${gnugrep}";

  builder = "/usr/bin/bash";
  args = [ ./builder.sh ];

  PATH = "/usr/bin:/usr/sbin";
}
