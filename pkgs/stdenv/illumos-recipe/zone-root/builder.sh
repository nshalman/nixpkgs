#!/usr/bin/bash
#
# Required environment (set by make-zone-root.nix derivation attrs):
#   $out             output path (the .tar.xz file)
#   $smartosLive     path to a built smartos-live tree
#   $manifestList    path to the SMF manifest list (services + states)
#   $createSmfRepo   path to the create-smf-repo.sh helper
#   $xzPath          nix-built xz
#   $gnutarPath      nix-built gnutar
#   $rsyncPath       nix-built rsync
#   $gnugrepPath     nix-built gnugrep (used by create-smf-repo if needed)
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

# --- 3. Cleanups + /etc/profile fix ------------------------------------------
# Remove legacy SMF startup rc2.d scripts (SMF replaces them anyway).
# Remove /etc/issue (set by zone tooling at provision time).
# Remove SDC-specific root crontab (we don't run SDC tooling).
# Fix the /bin/i386 check in /etc/profile (the path doesn't exist on a
# clean illumos; substitute a uname check).
rm -f "$root/etc/rc2.d"/S*
rm -f "$root/etc/issue"
rm -f "$root/etc/cron.d/crontabs/root"
if [ -f "$root/etc/profile" ]; then
    ed -s "$root/etc/profile" <<'EOF' || true
/bin.i386/
s,/bin/i386,[ `uname -p` = "i386" ],
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

# --- 5. Apply ownership/mode from smartos-live manifest.gen ------------------
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

# --- 6. Pack -----------------------------------------------------------------
# Reproducible flags mirror make-bootstrap-tools / make-zone-image.
cd "$root"
XZ_OPT="-6 -T 4" "$tar" cJf "$out" \
    --hard-dereference --sort=name --numeric-owner --owner=0 --group=0 --mtime=@1 \
    .

echo "zone-root built: $out"
