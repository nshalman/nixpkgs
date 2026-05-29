#!/usr/bin/bash
#
# Required environment (set by make-zone-root.nix derivation attrs):
#   $out             output path (the .tar.xz file)
#   $smartosLive     path to a built smartos-live tree
#   $manifestList    path to the SMF manifest list (services + states)
#   $createSmfRepo   path to the create-smf-repo.sh helper
#   $xzPath          nix-built xz
#   $gnutarPath      nix-built gnutar
#   $rsyncPath       nix-built rsync (used for proto/etc + proto/var copy)
#   $gnugrepPath     nix-built gnugrep (used by create-smf-repo if needed)
#   $profileFile     /etc/profile to lay down (overwrites proto's)
#   $systemNix       system.nix template installed at /etc/nixos/system.nix
#
# Adapted from MNX Cloud's imagetools/create-seed
# (https://github.com/MNX-Cloud/imagetools). The pkgsrc-specific user
# deletions (lp/gdm/mysql/openldap/webservd/postgres from passwd/shadow/
# group/user_attr) are dropped — we don't ship pkgsrc in this zone.
# The zoneinit + S99final hooks are dropped — nix owns first-boot for
# us. The smartos-live overlay step is dropped — modern smartos-live
# trees don't ship that directory anymore.

set -euo pipefail
set -o xtrace

xz="$xzPath/bin/xz"
tar="$gnutarPath/bin/tar"
rsync="$rsyncPath/bin/rsync"

[ -x "$xz" ]    || { echo "missing xz at $xz" >&2; exit 1; }
[ -x "$tar" ]   || { echo "missing tar at $tar" >&2; exit 1; }
[ -x "$rsync" ] || { echo "missing rsync at $rsync" >&2; exit 1; }
[ -d "$smartosLive/proto" ] || { echo "smartosLive=$smartosLive has no proto/" >&2; exit 1; }
[ -f "$smartosLive/manifest.gen" ] || { echo "no manifest.gen in $smartosLive" >&2; exit 1; }

root="$PWD/root"
mkdir -p "$root"

# --- 1. Skeleton dirs + symlink ----------------------------------------------
for dir in home root var/ssh; do
    mkdir -p "$root/$dir"
done
mkdir -p -m 1777 "$root/tmp"
ln -s ./usr/bin "$root/bin"

# --- 2. Copy proto/etc and proto/var -----------------------------------------
for dir in etc var; do
    "$rsync" -a "$smartosLive/proto/$dir" "$root/"
done

# --- 3. Cleanups ---------------------------------------------------------------
# Remove legacy SMF startup rc2.d scripts (SMF replaces them anyway).
# Remove /etc/issue (set by zone tooling at provision time).
# Remove SDC-specific root crontab (we don't run SDC tooling).
rm -f "$root/etc/rc2.d"/S*
rm -f "$root/etc/issue"
rm -f "$root/etc/cron.d/crontabs/root"

# /etc/profile: overwrite proto's with our nix-aware version. (See
# zone-root/profile for content.) We own this file rather than patching
# proto's because the patches needed are large enough that owning is
# cleaner — and matches NixOS's convention of generating /etc/profile.
install -m 0644 "$profileFile" "$root/etc/profile"

# /etc/nixos/system.nix: editable equivalent of NixOS's configuration.nix.
# Documented at the top of the file; tl;dr `nix-build /etc/nixos/system.nix
# -o /nix/var/nix/profiles/default` to rebuild and swap the system profile.
mkdir -p "$root/etc/nixos"
install -m 0644 "$systemNix" "$root/etc/nixos/system.nix"

# Root shadow: proto/etc ships `root::...` (empty password), which
# pam_authtok_get rejects with "empty password not allowed". Stock
# SmartOS uses `NP` ("no password required"), which lets `zlogin
# <uuid>` (without -S) drop straight to a root shell from the global
# zone. Substitute on the leading field only.
if [ -f "$root/etc/shadow" ]; then
    ed -s "$root/etc/shadow" <<'EOF' || true
/^root::/
s,^root::,root:NP:,
w
q
EOF
fi

# Root shell: proto/etc/passwd sets it to /usr/bin/bash which lives in
# the GZ-bind-mounted /usr inside a joyent zone. Switch to the bash
# under the nix system profile — a stable indirection that survives
# profile-rebuild swaps without needing /etc/passwd edits.
if [ -f "$root/etc/passwd" ]; then
    ed -s "$root/etc/passwd" <<'EOF' || true
/^root:/
s,:/usr/bin/bash$,:/nix/var/nix/profiles/default/bin/bash,
w
q
EOF
fi

# --- 4. SMF repository -------------------------------------------------------
# create-smf-repo imports every manifest listed in $manifestList into a
# fresh repository.db using svccfg pointed at our staging path.
mkdir -p "$root/etc/svc"
SMARTOS_LIVE="$smartosLive" \
GNUGREP="$gnugrepPath/bin/grep" \
    "$createSmfRepo" "$manifestList" "$root/etc/svc/repository.db"

# --- 5. zoneinit features declaration ----------------------------------------
# vmadm's checkDatasetProvisionable() rejects the dataset unless
# /var/zoneinit/zoneinit.json declares features.var_svc_provisioning =
# true. The brand `joyent` does NOT set this in BRAND_OPTIONS, so vmadm
# falls through to the dataset check and refuses to provision without
# the file. We don't ship the imagetools S99final hook (we drop into a
# nix-managed runtime, not zoneinit's), but the bare features
# declaration is enough.
mkdir -p "$root/var/zoneinit"
cat > "$root/var/zoneinit/zoneinit.json" <<'JSON'
{
  "version": "1.5.1",
  "features": {
    "var_svc_provisioning": true,
    "reboot": true
  }
}
JSON

# --- 6. Apply ownership/mode from smartos-live manifest.gen ------------------
# manifest.gen lines look like:
#   <type> <relpath> <mode> <owner> <group> [...]
# where type is f/d/l (file/dir/link). We honor f and d; symlinks
# inherit their target's perms on illumos.
#
# This is the only "long, slow" step. 26k manifest.gen lines * a chmod
# + chown each. Filter to entries that actually exist in $root so we
# don't waste calls on things proto/ didn't ship.
while read ftype file mode owner group _rest; do
    target="$root/$file"
    case "$ftype" in
    d)
        if [ -d "$target" ]; then
            chmod "$mode" "$target"
            chown "$owner:$group" "$target"
        fi
        ;;
    f)
        if [ -f "$target" ]; then
            chmod "$mode" "$target"
            chown "$owner:$group" "$target"
        fi
        ;;
    esac
done < "$smartosLive/manifest.gen"

# --- 7. Pack -----------------------------------------------------------------
# Reproducible flags mirror make-bootstrap-tools / make-zone-image.
cd "$root"
XZ_OPT="-6 -T 4" "$tar" cJf "$out" \
    --hard-dereference --sort=name --numeric-owner --owner=0 --group=0 --mtime=@1 \
    .

echo "zone-root built: $out"
