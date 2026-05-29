#!/usr/bin/env bash
#
# Build a joyent-brand zone image (`.zfs.gz` + `.imgmanifest`) from the
# layered nix-zone-image.tar.xz + illumos-zone-root.tar.xz tarballs.
#
# Impure: this is NOT a nix-driven build. The script needs:
#   - root (or `pfexec`) so it can `zfs create`, snapshot, and `zfs send`.
#   - /usr/sbin/zfs on PATH.
#   - gzip + sha1sum (or `digest -a sha1` on illumos) + tar.
#
# Usage:
#   make-joyent-image.sh \
#       --parent-dataset zones \
#       --zone-image     /nix/store/<hash>-nix-zone-image.tar.xz \
#       --zone-root      /nix/store/<hash>-illumos-zone-root.tar.xz \
#       --name           nix-test-zone \
#       --version        0.1.0 \
#       --out-dir        ./out \
#       [--description   "...text..."] \
#       [--keep-dataset]
#
# Produces (in $OUT_DIR):
#   <uuid>.zfs.gz         the zfs send stream, gzip-compressed
#   <uuid>.imgmanifest    IMGAPI v2 manifest, ready for `imgadm install`
#
# After the build the temp dataset (`$PARENT_DATASET/<uuid>`) is
# destroyed unless --keep-dataset is passed.
#
# DB pre-population
# -----------------
# Both build host and target zone use /nix/store as the actual store
# directory. nix-store accepts a NIX_STATE_DIR env var override at
# runtime (only NIX_STORE_DIR is compile-time-fixed), so we can run
# the image's own nix-store binary on the host, pointed at the
# dataset's nix/var/nix, and have it write the DB into the dataset's
# /nix/var/nix/db/db.sqlite.
#
# Using the *image's* nix-store (not the bootstrap nix-store) keeps
# the on-disk DB schema matched to the nix that will read it at boot.

set -euo pipefail

# --- arg parsing -------------------------------------------------------------
PARENT_DATASET=""
ZONE_IMAGE=""
ZONE_ROOT=""
NAME=""
VERSION=""
DESCRIPTION="Nix-on-illumos zone"
OUT_DIR=""
KEEP_DATASET=0
# Path to a GNU tar. Required because illumos /usr/bin/tar can't
# unpack archives that use the @LongLink extension for paths > 100
# chars (which nix-store's deeply-nested store paths frequently
# trigger). Defaults to whatever `tar` is on PATH, but the .nix
# wrapper passes the explicit nix-built gnutar to be safe.
GTAR="tar"

usage() {
    sed -n '2,$p' "$0" | sed -n '/^# Usage:/,/^# First-boot/p' | sed 's/^# //;s/^#$//'
    exit "${1:-2}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --parent-dataset)  PARENT_DATASET="$2"; shift 2 ;;
        --zone-image)      ZONE_IMAGE="$2";     shift 2 ;;
        --zone-root)       ZONE_ROOT="$2";      shift 2 ;;
        --name)            NAME="$2";           shift 2 ;;
        --version)         VERSION="$2";        shift 2 ;;
        --description)     DESCRIPTION="$2";    shift 2 ;;
        --out-dir)         OUT_DIR="$2";        shift 2 ;;
        --gtar)            GTAR="$2";           shift 2 ;;
        --keep-dataset)    KEEP_DATASET=1;      shift ;;
        -h|--help)         usage 0 ;;
        *) echo "unknown arg: $1" >&2; usage ;;
    esac
done

required="PARENT_DATASET ZONE_IMAGE ZONE_ROOT NAME VERSION OUT_DIR"
for v in $required; do
    if [[ -z "${!v:-}" ]]; then
        echo "missing --$(echo "$v" | tr '[:upper:]_' '[:lower:]-')" >&2
        usage
    fi
done

for f in "$ZONE_IMAGE" "$ZONE_ROOT"; do
    [[ -f "$f" ]] || { echo "not found: $f" >&2; exit 1; }
done

command -v zfs   >/dev/null 2>&1 || { echo "zfs not on PATH" >&2; exit 1; }
command -v gzip  >/dev/null 2>&1 || { echo "gzip not on PATH" >&2; exit 1; }
command -v "$GTAR" >/dev/null 2>&1 || { echo "tar not found: $GTAR" >&2; exit 1; }

# uuid generator: prefer `uuidgen` if present; fall back to /proc/sys
# or a python one-liner; illumos has uuidgen via libuuid in /usr/bin.
if command -v uuidgen >/dev/null 2>&1; then
    UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
elif command -v python3 >/dev/null 2>&1; then
    UUID=$(python3 -c 'import uuid; print(str(uuid.uuid4()))')
else
    echo "need uuidgen or python3 to generate a uuid" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
OUT_DIR=$(cd "$OUT_DIR" && pwd)

DATASET="$PARENT_DATASET/$UUID"

cleanup() {
    if [[ "$KEEP_DATASET" = 0 ]]; then
        zfs destroy -r "$DATASET" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# --- 1. Create + populate the dataset ----------------------------------------
zfs create "$DATASET"
MOUNT=$(zfs get -H -o value mountpoint "$DATASET")
[[ "$MOUNT" != "-" && -d "$MOUNT" ]] || {
    echo "no mountpoint for $DATASET (got '$MOUNT')" >&2
    exit 1
}

# joyent zone layout puts the zone's root filesystem at $DATASET/root.
ROOT="$MOUNT/root"
mkdir -p "$ROOT"

# Unpack both tarballs into $ROOT. Order: zone-image first (provides
# /nix and /etc/nix), then zone-root (provides /etc, /var, /home, ...).
# zone-root's /etc/ doesn't ship a /etc/nix/ subtree, so the
# nix.conf from zone-image survives.
echo "unpacking zone-image into $ROOT ..."
xz -dc "$ZONE_IMAGE" | "$GTAR" xf - -C "$ROOT"
echo "unpacking zone-root into $ROOT ..."
xz -dc "$ZONE_ROOT"  | "$GTAR" xf - -C "$ROOT"

# --- 2. Pre-populate /nix/var/nix/db/db.sqlite -------------------------------
# Use the image's *own* nix-store binary (pointed at by
# /nix/var/nix/profiles/default) so the DB schema matches what the zone
# will read at boot. Override NIX_STATE_DIR to redirect the write into
# the dataset; NIX_STORE_DIR stays at the compile-time /nix/store
# (which the host also has, populated identically — this is the same
# host that built the image).
PROFILE_TARGET=$(readlink "$ROOT/nix/var/nix/profiles/default")
[[ -n "$PROFILE_TARGET" ]] || { echo "no profiles/default symlink" >&2; exit 1; }
NIX_BIN="$ROOT$PROFILE_TARGET/bin/nix-store"
[[ -x "$NIX_BIN" ]] || { echo "missing nix-store at $NIX_BIN" >&2; exit 1; }

echo "loading nix store DB ..."
NIX_STATE_DIR="$ROOT/nix/var/nix" \
    "$NIX_BIN" --load-db < "$ROOT/nix/var/nix/.reginfo"

# --- 3. Snapshot + zfs send | gzip -------------------------------------------
zfs snapshot "$DATASET@final"

OUT_DATA="$OUT_DIR/$UUID.zfs.gz"
echo "writing $OUT_DATA ..."
zfs send "$DATASET@final" | gzip -c > "$OUT_DATA"

# --- 4. Compute sha1 + size --------------------------------------------------
if command -v sha1sum >/dev/null 2>&1; then
    SHA1=$(sha1sum "$OUT_DATA" | awk '{print $1}')
elif command -v digest >/dev/null 2>&1; then
    SHA1=$(digest -a sha1 "$OUT_DATA")
else
    echo "need sha1sum or digest" >&2
    exit 1
fi

if stat -c%s "$OUT_DATA" >/dev/null 2>&1; then
    SIZE=$(stat -c%s "$OUT_DATA")
else
    SIZE=$(stat -f%z "$OUT_DATA" 2>/dev/null || wc -c < "$OUT_DATA" | tr -d ' ')
fi

PUBLISHED_AT=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

# --- 5. Emit the manifest ----------------------------------------------------
# Shape matches the example minimal-64-lts manifest from
# images.tritondatacenter.com (zone-dataset, gzip-compressed file).
# `requirements.min_platform` and `requirements.networks` mirror the
# reference; tighten / loosen as needed for the target environment.
MANIFEST="$OUT_DIR/$UUID.imgmanifest"

cat > "$MANIFEST" <<EOF
{
  "v": 2,
  "uuid": "$UUID",
  "owner": "00000000-0000-0000-0000-000000000000",
  "name": "$NAME",
  "version": "$VERSION",
  "state": "active",
  "disabled": false,
  "public": false,
  "published_at": "$PUBLISHED_AT",
  "type": "zone-dataset",
  "os": "smartos",
  "files": [
    {
      "sha1": "$SHA1",
      "size": $SIZE,
      "compression": "gzip"
    }
  ],
  "description": "$DESCRIPTION",
  "requirements": {
    "min_platform": {
      "7.0": "20210826T002459Z"
    },
    "networks": [
      {
        "name": "net0",
        "description": "public"
      }
    ]
  },
  "tags": {
    "role": "os"
  }
}
EOF

cat <<EOF

Done.

  manifest: $MANIFEST
  image:    $OUT_DATA  ($SIZE bytes, sha1 $SHA1)

Install:

  imgadm install -m $MANIFEST -f $OUT_DATA

The image ships with /nix/var/nix/db/db.sqlite already populated, so
the zone's nix-store works out of the box on first boot.

EOF
