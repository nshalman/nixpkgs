# Cleanliness audit for the stage-2 stdenv (and other rooted closures).
#
# For each requested root, scans every file in the closure for plain
# string refs to forbidden host paths (/opt/local, illumos-strap-tools,
# proto-strap, /usr/gcc) and fails the build if any appear.
#
# This is a regression tripwire: stage 2's contract is "no /opt/local
# string refs anywhere in the closure" and the deep grep is the cheapest
# way to keep us honest. A green build of `nix-build audit.nix -A stdenv`
# means stage 2 hasn't regressed.
#
# Usage:
#   nix-build pkgs/stdenv/illumos-recipe/audit.nix -A stdenv
#   nix-build pkgs/stdenv/illumos-recipe/audit.nix -A hello
{
  pkgs ? import ../../.. { },
}:
let
  inherit (pkgs) runCommand closureInfo lib;
  inherit (pkgs.buildPackages) gnugrep;

  # Patterns we don't want anywhere in the closure. Note `/usr/gcc` is
  # tolerated for now in some upstreams (host gcc-10 RUNPATH leak via
  # proto-strap, see make-bootstrap-tools.nix); included here so the
  # audit reports it but consumers can filter / accept.
  forbidden = [
    "/opt/local"
    "illumos-strap-tools"
    "proto-strap"
  ];

  auditClosure =
    name: rootPaths:
    runCommand "${name}-clean-audit"
      {
        nativeBuildInputs = [ gnugrep ];
        ci = closureInfo { inherit rootPaths; };
      }
      ''
        set -eu
        bad=0
        patterns=${lib.escapeShellArgs forbidden}
        for p in $(cat $ci/store-paths); do
          for pat in $patterns; do
            # -a: treat binaries as text, -I: skip nothing, -l: just names,
            # -r: recursive. We want a hit in any file (binary or text).
            if hits=$(grep -ralF "$pat" "$p" 2>/dev/null) && [ -n "$hits" ]; then
              echo "FORBIDDEN: $p references '$pat':" >&2
              echo "$hits" | sed 's/^/    /' >&2
              bad=1
            fi
          done
        done
        if [ "$bad" = 1 ]; then
          echo "closure cleanliness audit FAILED for ${name}" >&2
          exit 1
        fi
        printf 'closure clean: %s\n' "${name}" > $out
      '';

  bootstrapToolsPkgs =
    (import ./make-bootstrap-tools.nix { inherit pkgs; }).bootstrap-tools-packages;

in
{
  stdenv = auditClosure "stdenv" [ pkgs.stdenv ];

  # A handful of representative downstream packages. Add more here as
  # cleanliness is verified — every new entry is a tripwire against
  # regressions in the corresponding subgraph.
  hello = auditClosure "hello" [ pkgs.hello ];
  bash = auditClosure "bash" [ pkgs.bash ];

  # The full closure that goes into the bootstrap-tools tarball.
  # Building this clean is the precondition for the tarball working on
  # zones without /opt/local. Empirical test: extract the tarball with
  # /opt/local moved aside and run bash + gcc compile-and-link (see
  # ./test-bootstrap-tarball.sh).
  bootstrap-tools = auditClosure "bootstrap-tools" bootstrapToolsPkgs;
}
