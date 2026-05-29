# Build a zone-root tarball for x86_64-illumos.
#
# Usage:
#   nix-build pkgs/stdenv/illumos-recipe/make-zone-root.nix \
#     --argstr smartosLive /workspace/smartos-live
#
# Produces:
#   result    a tar.xz of the SmartOS-style zone root (/etc, /var,
#             /home, /root, /tmp, /var/ssh, /etc/svc/repository.db, ...).
#             Combine with nix-zone-image.tar.xz at extraction time to
#             get a complete zone root that boots SMF and has nix.
#
# Architecture
# ------------
# This derivation orchestrates a port of MNX Cloud's `imagetools/create-seed`
# (https://github.com/MNX-Cloud/imagetools) minus the parts that are
# pkgsrc-specific (passwd/shadow/group user deletions for UID-collision
# avoidance — we don't use pkgsrc in our zones) and minus the zoneinit
# bits (nix owns first-boot for us).
#
# What it does, in order:
#   1. Lay down skeleton dirs (/home, /root, /var/ssh, /tmp 1777, /bin
#      -> ./usr/bin symlink).
#   2. Copy ${smartosLive}/proto/etc and proto/var into the staging root.
#   3. Drop legacy /etc/rc2.d/S* startup scripts, /etc/issue, the
#      SDC-specific root crontab, and fix /etc/profile's /bin/i386 hack.
#   4. Build /etc/svc/repository.db by importing every manifest listed
#      in ${./zone-root/manifests} via the smartos-live build's
#      proto/usr/sbin/svccfg + proto/lib/svc/bin/svc.configd (which
#      replace the old -native variants the original create-smf-repo
#      expected).
#   5. Apply file modes/owners from ${smartosLive}/manifest.gen.
#   6. tar+xz the result.
#
# What it intentionally does NOT do (yet):
#   - Apply the smartos-live `overlay/generic/etc/` layer. This tree
#     lives in the smartos-live SOURCE checkout, not the build proto.
#     Layer in via the consumer or a follow-up derivation once we
#     decide where its inputs live.
#   - Layer in imagetools' own overlay/etc/ (skel/, motd, resolv.conf,
#     S99net_tune). Follow-up.
#   - mdata.xml import for SDC mdata-client. Follow-up if we end up
#     wanting that contract in the zone.
#
# Inputs (impure)
# ---------------
# This derivation is intentionally impure: smartosLive is a path on
# disk, not a nix store artifact. illumos nix has no build sandbox, so
# we just cd into it and read. The build is reproducible only insofar
# as the smartos-live tree is held constant.
{
  pkgs ? import ../../.. { },
  # Absolute path to a built smartos-live tree.
  smartosLive ? "/workspace/smartos-live",
  # bash-interactive 5.3p3, pinned to the same store path
  # make-zone-image.nix uses so root's login shell (substituted into
  # /etc/passwd below) resolves to the bash this image actually ships.
  # Update both pins together when bash gets rebuilt.
  bash ? builtins.storePath /nix/store/b9fi3f6i5ccfyli18bnkgqpq2h2fzrds-bash-interactive-5.3p3,
  system ? "x86_64-illumos",
}:
let
  inherit (pkgs.buildPackages) xz gnutar rsync;
  inherit (pkgs) gnugrep;
in
derivation {
  name = "illumos-zone-root.tar.xz";
  inherit system;

  inherit smartosLive;
  rootShell = "${bash}/bin/bash";
  manifestList = ./zone-root/manifests;
  createSmfRepo = ./zone-root/create-smf-repo.sh;
  builder = "/usr/bin/bash";
  args = [ ./zone-root/builder.sh ];

  # /usr/bin: ed, mkdir, ln, chmod, chown, find, sort, basename
  # xz + gnutar: for the final pack step
  # rsync: used for all copy operations across the illumos-recipe
  #        tooling (consistent with make-bootstrap-tools.nix and
  #        make-zone-image.nix); preserves modes including exec bits,
  #        symlinks, and hardlinks without the cp `--no-preserve=mode`
  #        gotcha that yielded non-executable binaries.
  # gnugrep: not strictly needed for the current builder, but available
  #          if create-smf-repo grows a grep-on-binary case (illumos
  #          /usr/bin/grep is SUSv2-only, no -a).
  xzPath = "${xz}";
  gnutarPath = "${gnutar}";
  rsyncPath = "${rsync}";
  gnugrepPath = "${gnugrep}";

  PATH = "/usr/bin:/usr/sbin";
}
