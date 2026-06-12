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
#   $nixDaemonManifest  SMF manifest XML for the nix-daemon service
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
# illumos /usr/bin/install is SUS-syntax (install -c -m mode src destdir),
# not GNU `install -m mode src dst` — use plain cp + chmod instead.
cp "$profileFile" "$root/etc/profile"
chmod 0644 "$root/etc/profile"

# /etc/nixos/system.nix: editable equivalent of NixOS's configuration.nix.
# Documented at the top of the file; tl;dr `nix-build /etc/nixos/system.nix
# -o /nix/var/nix/profiles/default` to rebuild and swap the system profile.
mkdir -p "$root/etc/nixos"
cp "$systemNix" "$root/etc/nixos/system.nix"
chmod 0644 "$root/etc/nixos/system.nix"

# /etc/ssl/certs: provide both standard filenames as symlinks into the
# Mozilla CA bundle that pkgs.cacert ships under the system profile.
# illumos's proto /etc has /etc/openssl/ (openssl config dir) but no
# /etc/ssl/, so apps like git/curl/wget that hardcode
# /etc/ssl/certs/ca-bundle.crt (RHEL convention) or
# /etc/ssl/certs/ca-certificates.crt (Debian convention) both find the
# bundle. ca-certificates.crt is a relative symlink so it follows the
# same indirection.
mkdir -p "$root/etc/ssl/certs"
ln -sf /nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt \
    "$root/etc/ssl/certs/ca-bundle.crt"
ln -sf ca-bundle.crt "$root/etc/ssl/certs/ca-certificates.crt"

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

# nixbld build users + group. nix's standalone build-user mechanism
# (build-users-group = nixbld in nix.conf) requires `nixbld` group's
# gr_mem field to list every nixbldN explicitly — SimpleUserLock::
# acquire enumerates gr_mem, not users whose primary group is nixbld.
# We write the proto-derived /etc/{passwd,shadow,group} directly rather
# than calling useradd: useradd isn't in this builder's PATH, and
# illumos `useradd -g` doesn't populate gr_mem anyway.
mkdir -p "$root/var/empty"
chmod 555 "$root/var/empty"
members=""
i=1
while [ "$i" -le 32 ]; do
    user="nixbld${i}"
    uid=$((30000 + i))
    echo "${user}:x:${uid}:30000:Nix build user ${i}:/var/empty:/usr/bin/false" >> "$root/etc/passwd"
    echo "${user}:*LK*:::::::"                                                  >> "$root/etc/shadow"
    members="${members}${members:+,}${user}"
    i=$((i + 1))
done
echo "nixbld:!:30000:${members}" >> "$root/etc/group"

# --- 4. SMF repository -------------------------------------------------------
# create-smf-repo imports every manifest listed in $manifestList into a
# fresh repository.db using svccfg pointed at our staging path.
mkdir -p "$root/etc/svc"
SMARTOS_LIVE="$smartosLive" \
GNUGREP="$gnugrepPath/bin/grep" \
    "$createSmfRepo" "$manifestList" "$root/etc/svc/repository.db"

# Import the nix-daemon manifest into the same repository.db. We
# don't list it in $manifestList because create-smf-repo only looks
# under $smartosLive/proto/lib/svc/manifest/, and shipping a custom
# manifest into that tree would mean polluting the smartos-live proto.
# Calling svccfg directly with SVCCFG_REPOSITORY pointed at our staging
# db is the same mechanism create-smf-repo uses internally; the result
# is a single repository.db that contains both the standard smartos
# services and our nix-daemon service.
chmod u+w "$root/etc/svc/repository.db"
SVCCFG_REPOSITORY="$root/etc/svc/repository.db" \
SVCCFG_CONFIGD_PATH="$smartosLive/proto/lib/svc/bin/svc.configd" \
    "$smartosLive/proto/usr/sbin/svccfg" import "$nixDaemonManifest"
chmod 444 "$root/etc/svc/repository.db"

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
