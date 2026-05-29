# Nix-driven wrapper around make-joyent-image.sh.
#
# Closes over the two tarballs (zone-image + zone-root), passes them to
# the impure shell driver, and lands the resulting `.zfs.gz` +
# `.imgmanifest` pair in $out.
#
# Usage:
#   nix-build pkgs/stdenv/illumos-recipe/make-joyent-image.nix \
#     --argstr parentDataset zones/<gz-uuid>/data \
#     [--argstr smartosLive  /workspace/smartos-live] \
#     [--argstr name         nix-test-zone] \
#     [--argstr version      0.1.0] \
#     [--argstr description  "..."]
#
# Impure: needs root (or `pfexec`) so the builder can `zfs create`,
# snapshot, and `zfs send`. illumos nix doesn't sandbox, so this works
# transparently; on other platforms this derivation would not.
#
# Output layout (under $out):
#   <uuid>.zfs.gz
#   <uuid>.imgmanifest
#
# Realise then install:
#   nix-build ... -A image
#   imgadm install -m result/<uuid>.imgmanifest -f result/<uuid>.zfs.gz
{
  pkgs ? import ../../.. { },

  # The parent ZFS dataset under which to create the temp child
  # (mounts at /<parent>/<uuid>) for tarball unpack + snapshot + send.
  parentDataset,

  # Path to a built smartos-live tree (used by make-zone-root.nix's
  # proto-copy step). Pass through transparently.
  smartosLive ? "/workspace/smartos-live",

  # The two layered tarballs. Default to what the sibling derivations
  # produce; override to point at out-of-band-built artifacts.
  zoneImage ? (import ./make-zone-image.nix { inherit pkgs; }).zone-image,
  zoneRoot ? import ./make-zone-root.nix { inherit pkgs smartosLive; },

  # Image identity. UUID is generated inside the builder.
  name ? "nix-zone",
  version ? "0.1.0",
  description ? "Nix-on-illumos zone image",
}:
let
  inherit (pkgs) lib;
  inherit (pkgs.buildPackages) gnutar;
in
{
  image = derivation {
    name = "joyent-image-${name}-${version}";
    system = "x86_64-illumos";

    inherit parentDataset zoneImage zoneRoot;
    imageName = name;
    imageVersion = version;
    imageDescription = description;
    # illumos /usr/bin/tar can't unpack the GNU tar @LongLink
    # extension; pass the nix-built gnutar explicitly.
    gtarPath = "${gnutar}/bin/tar";

    builder = "/usr/bin/bash";
    args = [ ./make-joyent-image-nix-builder.sh ];

    # Script is impure; needs zfs, gzip, sha1sum/digest, uuidgen
    # — all of which live under /usr/{bin,sbin} on the host.
    PATH = "/usr/bin:/usr/sbin";

    # Reference the .sh driver so any change forces a rebuild.
    driver = ./make-joyent-image.sh;
  };
}
