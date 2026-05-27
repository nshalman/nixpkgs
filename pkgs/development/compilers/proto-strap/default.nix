# proto-strap: SmartOS-published GCC + binutils + gas strap, extracted
# into the nix store as a host-toolchain input for gcc-illumos.
#
# What this is: the SmartOS bootstrap-cache artifact produced by Jenkins
# at https://us-central.manta.mnx.io/Joyent_Dev/public/builds/SmartOS/
# strap-cache/master/<pkgsrc_branch>/<arch>/<sha>/<timestamp>/. It
# contains:
#
#   usr/gcc/10/bin/{gcc,g++,cpp,...}      GCC 10.4.0 (the SmartOS-recipe
#                                          build of github.com/illumos/gcc
#                                          gcc-10.x tagged tree)
#   usr/gnu/bin/{gas,gld,gar,...}         GNU binutils / gas
#   usr/lib/...                           support libs
#   ...
#
# What it is NOT: a full build environment. It does not ship bash, make,
# sed, awk, gawk, tar, patch, m4, flex, or bison — those still come from
# the host (illumos /usr/bin + pkgsrc /opt/local for the bits illumos
# itself doesn't carry).
#
# Why we want it: the SmartOS proto.strap GCC is clean of /opt/local
# pollution — its RUNPATH is /usr/gcc/10/lib/amd64, not anything pkgsrc.
# Using it as gcc-illumos's host compiler means stage-1 xgcc has no
# pkgsrc linkage to scrub.
#
# Relocation: proto.strap GCC binaries have RUNPATH hardcoded to
# /usr/gcc/10/lib/amd64. The GCC binary itself works from any path
# because it finds its own libs via relative -B paths embedded in its
# specs at configure time. The runtime libs it produces *for* binaries
# it links carry the same /usr/gcc/10/lib/amd64 RUNPATH — that's a
# concern for the gcc-illumos build downstream, not for this derivation.
#
# Pinning: we pin a specific timestamped Manta URL (not /latest) so the
# hash is stable. Bump version + hash to update.

{
  # Override these to pin a different strap-cache build. The default is
  # the build active at 2026-05-27. To find a newer one, browse:
  #   https://us-central.manta.mnx.io/Joyent_Dev/public/builds/SmartOS/strap-cache/master/2024Q4/x86_64/
  # Each <sha>/latest file resolves to the newest timestamped subdir.
  pkgsrcBranch ? "2024Q4",
  arch ? "x86_64",
  illumosExtraSha ? "b552fd0e50cc02bafa0beadd5012cb06a3fd0714",
  timestamp ? "20260527T142255Z",
  # sha256 must be re-computed (e.g. nix-prefetch-url) when any of the
  # above are bumped.
  sha256 ? "11p0pdybsz3hbgx05vdfzzm4h9ha4jvxn1rp3wj9nv34ibgikh67",
  system ? "x86_64-illumos",
}:

let
  fetchurl = import <nix/fetchurl.nix>;

  url =
    "https://us-central.manta.mnx.io/Joyent_Dev/public/builds/SmartOS"
    + "/strap-cache/master/${pkgsrcBranch}/${arch}"
    + "/${illumosExtraSha}/${timestamp}/proto.strap.tar.gz";

  tarball = fetchurl {
    inherit url sha256;
    name = "proto.strap-${timestamp}.tar.gz";
  };

in
derivation {
  name = "proto-strap-${timestamp}";
  inherit system tarball;

  builder = "/usr/bin/bash";
  args = [ ./builder.sh ];

  # Tools needed by the unpack step. /usr/bin/tar can handle gzip on
  # illumos, so no extra PATH needed beyond the system shell.
  unpackPath = "/usr/bin";
}
