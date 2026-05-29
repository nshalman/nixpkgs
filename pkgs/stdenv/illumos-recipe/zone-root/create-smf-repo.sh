#!/usr/bin/bash
#
# Required environment:
#   $SMARTOS_LIVE   path to a built smartos-live tree
#   $GNUGREP        path to nix-built GNU grep (illumos /usr/bin/grep is
#                   SUSv2-only and chokes on -a, so create-smf-repo needs
#                   the gnu variant for safe in-pipeline grepping)
#
# Usage: create-smf-repo.sh <manifest-list> <output-repository.db>
#
# Adapted from MNX Cloud's imagetools/create-smf-repo
# (https://github.com/MNX-Cloud/imagetools). Adapts to the modern
# smartos-live layout where the build produces unsuffixed svccfg +
# svc.configd binaries in proto/usr/sbin and proto/lib/svc/bin
# respectively (the old "-native" suffix is gone). Drops the
# MANIFESTS_LOCAL / overlay-generic / overlay-smartos search paths the
# old script tried, since modern smartos-live ships all manifests
# under proto/lib/svc/manifest.

if [ $# -ne 2 ]; then
    echo "usage: $0 <manifest-list> <output>" >&2
    exit 2
fi
MANIFEST_LIST="$1"; shift
OUTPUT="$1"; shift

[ -n "${SMARTOS_LIVE:-}" ] || { echo "SMARTOS_LIVE must be set" >&2; exit 2; }
[ -d "$SMARTOS_LIVE/proto" ] || { echo "$SMARTOS_LIVE has no proto/" >&2; exit 2; }

SVCCFG="$SMARTOS_LIVE/proto/usr/sbin/svccfg"
CONFIGD="$SMARTOS_LIVE/proto/lib/svc/bin/svc.configd"
MANIFESTS_PROTO="$SMARTOS_LIVE/proto/lib/svc/manifest"

[ -x "$SVCCFG" ]  || { echo "missing svccfg at $SVCCFG" >&2; exit 1; }
[ -x "$CONFIGD" ] || { echo "missing svc.configd at $CONFIGD" >&2; exit 1; }
[ -d "$MANIFESTS_PROTO" ] || { echo "missing manifests at $MANIFESTS_PROTO" >&2; exit 1; }

GREP="${GNUGREP:-grep}"

TMPFILE="$(mktemp -t create-smf-repo.XXXXXX)"
trap 'rm -f "$TMPFILE"' EXIT

fail() {
    echo "$*" >&2
    exit 1
}

# Find a manifest by its relative name under proto/lib/svc/manifest/,
# then re-emit it with the requested instance state (enabled/disabled).
# The state-flip is a textual nawk munge because we can't call libscf
# at this point (the repository.db doesn't exist yet — we're building it).
#
# Returns 0 on import success, 1 on missing-manifest (caller's choice).
import_manifest() {
    local rel="$1" want="$2"
    local mf="$MANIFESTS_PROTO/$rel"

    if [ ! -f "$mf" ]; then
        echo "WARN: manifest not found (skipping): $rel" >&2
        return 1
    fi

    nawk -v status="$want" '
{
    if (($1 == "<instance" && $2 == "name=\047default\047") ||
        $1 == "<create_default_instance") {
        if (status == "enabled")
            sub("\047false\047", "\047true\047")
        else
            sub("\047true\047",  "\047false\047")
    }
    print $0
}
' "$mf" > "$TMPFILE" || fail "nawk failed on $rel"

    "$SVCCFG" import "$TMPFILE" || fail "svccfg import failed: $rel"
}

build_database() {
    local input="$1" output="$2"

    export SVCCFG_REPOSITORY="$output"
    export SVCCFG_CONFIGD_PATH="$CONFIGD"
    rm -f "$SVCCFG_REPOSITORY"

    [ -f "$input" ] || fail "can't read manifest list: $input"

    # The manifest list is `<rel-path> <enabled|disabled>` per line,
    # with comments (#...) and blank lines allowed.
    #
    # Missing manifests log a warning and are skipped. The original
    # imagetools manifest list dates from older smartos-live; modern
    # trees have dropped some services (e.g., network/rpc/rex.xml).
    # Audit the WARN lines after the build to decide whether to update
    # the manifest list or restore the missing services from elsewhere.
    local skipped=0 imported=0
    while read svc state _rest; do
        [ -z "$svc" ] && continue
        case "$svc" in
            \#*) continue ;;
        esac
        if import_manifest "$svc" "$state"; then
            echo "$svc $state"
            imported=$((imported + 1))
        else
            skipped=$((skipped + 1))
        fi
    done < "$input"
    echo "create-smf-repo: imported $imported manifests, skipped $skipped missing"
}

build_database "$MANIFEST_LIST" "$OUTPUT"
chmod 444 "$OUTPUT"
echo "Generated $OUTPUT"
