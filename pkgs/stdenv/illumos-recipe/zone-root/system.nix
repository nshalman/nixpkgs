# /etc/nixos/system.nix — the configuration for a nix-on-illumos zone.
#
# This is the editable equivalent of /etc/nixos/configuration.nix on a
# NixOS host: the package set installed system-wide. To add or remove
# software, edit the `paths` list below.
#
# After editing, rebuild and switch the system profile in one atomic
# step:
#
#   nix-build /etc/nixos/system.nix -o /nix/var/nix/profiles/default
#
# (`nix-build -o` replaces the profile symlink atomically; bash, nix,
# and anything else under the merged bin/ pick up the new versions
# immediately.)
#
# `<nixpkgs>` must resolve to a checkout. Set NIX_PATH to point at one,
# e.g.:
#
#   nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs
#   nix-channel --update
#
# or just clone a working copy and `export NIX_PATH=nixpkgs=/path/to/nixpkgs`.
#
# Defaults below match what the zone-image's make-zone-image.nix
# initially builds, so the first nix-build of system.nix is a no-op
# (the profile already points at this content).
{ pkgs ? import <nixpkgs> { } }:

pkgs.buildEnv {
  name = "nix-zone-system";

  paths = with pkgs; [
    bashInteractive
    nixVersions.nix_2_33.out
    coreutils
    rsync
  ];

  pathsToLink = [ "/bin" "/etc" "/lib" "/libexec" "/share" ];
  ignoreCollisions = true;
}
