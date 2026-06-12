#!/usr/bin/env bash
# Idempotently set up the nixbld group + 32 build users + /nix/store
# perms required by nix's build-users-group support on illumos.
#
# Run as root in an existing illumos zone where nix is already installed
# (single-user or partial state). Safe to re-run.
#
# Does NOT modify /etc/nix/nix.conf. The order in which nix.conf gets
# flipped to `build-users-group = nixbld` matters when upgrading from
# an older (unpatched) nix to nix-2.33.6+12+; see the trailing notes
# this script prints.

set -euo pipefail

GROUP=nixbld
GID=30000
NUSERS=32
SHELL_PATH=/usr/bin/false
HOME_PATH=/var/empty
NIXCONF=/etc/nix/nix.conf

log() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ]            || err "must run as root"
[ "$(uname -s)" = SunOS ]     || err "illumos only (got $(uname -s))"

# /var/empty — home dir for the locked nixbld accounts.
if [ ! -d "$HOME_PATH" ]; then
    mkdir -p "$HOME_PATH"
    chmod 555 "$HOME_PATH"
    log "created $HOME_PATH"
fi

# nixbld group at fixed gid.
if getent group "$GROUP" >/dev/null; then
    cur=$(getent group "$GROUP" | cut -d: -f3)
    [ "$cur" = "$GID" ] || err "group $GROUP exists with gid $cur, expected $GID"
else
    groupadd -g "$GID" "$GROUP"
    log "created group $GROUP (gid $GID)"
fi

# nixbld1..N users at fixed uids.
created=0
for i in $(seq 1 "$NUSERS"); do
    user="nixbld$i"
    uid=$((GID + i))
    if getent passwd "$user" >/dev/null; then
        cur=$(getent passwd "$user" | cut -d: -f3)
        [ "$cur" = "$uid" ] || err "$user exists with uid $cur, expected $uid"
    else
        useradd -u "$uid" -g "$GID" -d "$HOME_PATH" -s "$SHELL_PATH" \
                -c "Nix build user $i" "$user"
        # Lock the account; idempotent if already locked.
        passwd -l "$user" >/dev/null 2>&1 || true
        created=$((created + 1))
    fi
done
if [ "$created" -eq 0 ]; then
    log "all $NUSERS nixbld users present"
else
    log "created $created nixbld user(s)"
fi

# /etc/group: nixbld's gr_mem must list every nixbldN explicitly.
# useradd -g sets the PRIMARY group but doesn't populate gr_mem, and
# nix's SimpleUserLock::acquire enumerates only gr_mem to pick a build
# user — without this, every build serializes on whichever nixbldN
# happens to be the lone gr_mem entry.
expected_members=$(seq 1 "$NUSERS" | sed 's/^/nixbld/' | paste -sd, -)
current_members=$(getent group "$GROUP" | cut -d: -f4)
if [ "$current_members" != "$expected_members" ]; then
    tmp=$(mktemp /etc/group.XXXXXX)
    awk -F: -v g="$GROUP" -v want="$expected_members" '
        BEGIN { OFS=":" }
        $1 == g { $4 = want }
        { print }
    ' /etc/group > "$tmp"
    chmod 644 "$tmp"
    mv "$tmp" /etc/group
    log "updated /etc/group: $GROUP gr_mem -> nixbld1..nixbld$NUSERS"
fi

# /nix/store: 1775 root:nixbld. chown+chmod are idempotent.
if [ -d /nix/store ]; then
    chown 0:"$GID" /nix/store
    chmod 1775 /nix/store
    log "ensured /nix/store ownership 0:$GID mode 1775"
fi

# nix.conf — report only.
if [ -f "$NIXCONF" ]; then
    if grep -qE '^build-users-group = nixbld$' "$NIXCONF"; then
        log "$NIXCONF: build-users-group = nixbld (multi-user mode)"
    else
        log "$NIXCONF: build-users-group is unset (single-user mode)"
    fi
fi

v=$(nix --version 2>/dev/null | head -1 || true)
[ -n "$v" ] && log "nix: $v"

cat <<'EOF'

To upgrade from older (unpatched) nix to nix-2.33.6+12+:

  1. Verify /etc/nix/nix.conf has 'build-users-group =' (empty), NOT
     'build-users-group = nixbld'. The unpatched outer nix creates
     build dirs as root-only; the new inner nix under test tries to
     switch to a nixbld user and can't write there — test phase fails.
  2. nix-build -A nixVersions.nix_2_33 -o /tmp/new-nix  (nixpkgs tree
     with the useBuildUsers + killUser illumos patches).
  3. nix-build /etc/nixos/system.nix -o /nix/var/nix/profiles/default
  4. Set 'build-users-group = nixbld' in /etc/nix/nix.conf.

If 'nix --version' above shows 2.33.6+12 or later, the bootstrap is
already done and you can flip nix.conf freely.
EOF
