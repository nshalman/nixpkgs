# Cleanliness audit for the final stdenv (and other rooted closures).
#
# Two semantically distinct checks for forbidden host-system paths:
#
#  - closurePatterns: fails if any /nix/store path in the runtime
#    closure has the pattern in its name. This is what nix would
#    actually pull in at deploy time. Used for build-time-only
#    dependencies (proto-strap, illumos-strap-tools) — they may
#    still appear as dead substrings inside binaries (e.g. baked-in
#    configure args records) but those substrings don't make the
#    derivation depend on them.
#
#  - substringPatterns: deep-greps every file in the closure for
#    the literal pattern. Used for /opt/local because consumers can
#    `dlopen` or `exec` paths that nix never sees — a /opt/local
#    string baked into a binary IS a functional dep even if the
#    derivation graph doesn't know it.
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

  closurePatterns = [
    "illumos-strap-tools"
    "proto-strap"
  ];

  substringPatterns = [
    "/opt/local"
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

        closurePats=( ${lib.escapeShellArgs closurePatterns} )
        substringPats=( ${lib.escapeShellArgs substringPatterns} )

        # Closure-path check: fail if any forbidden derivation name is
        # in the runtime closure.
        for p in $(cat $ci/store-paths); do
          for pat in "''${closurePats[@]}"; do
            if [[ "$p" == *"$pat"* ]]; then
              echo "FORBIDDEN: closure contains '$pat' via $p" >&2
              bad=1
            fi
          done
        done

        # Substring deep-grep: fail if any forbidden literal string
        # appears in any closure file.
        for p in $(cat $ci/store-paths); do
          for pat in "''${substringPats[@]}"; do
            # -a: treat binaries as text, -l: just names, -r: recursive.
            if hits=$(grep -ralF "$pat" "$p" 2>/dev/null) && [ -n "$hits" ]; then
              echo "FORBIDDEN: $p substring-matches '$pat':" >&2
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

  # `bootstrap-tools` audit reflects what make-bootstrap-tools.nix
  # ships — the refresher mode's from-source closure. Let
  # make-bootstrap-tools choose its own pkgs (it pins
  # illumosUseBootstrapFiles=false; see that file's header) rather
  # than threading the audit's own pkgs through, which would point
  # the audit at a different closure when the dispatcher is in
  # bootstrap-files mode.
  bootstrapToolsPkgs =
    (import ./make-bootstrap-tools.nix { }).bootstrap-tools-packages;

in
{
  stdenv = auditClosure "stdenv" [ pkgs.stdenv ];

  # A handful of representative downstream packages. Add more here as
  # cleanliness is verified — every new entry is a tripwire against
  # regressions in the corresponding subgraph.
  hello = auditClosure "hello" [ pkgs.hello ];
  bash = auditClosure "bash" [ pkgs.bash ];

  # The stage-rebuilt gcc-illumos: the cc that backs stage 3. Audit this
  # specifically to catch any proto-strap leak — the whole point of
  # rebuilding gcc-illumos in nixpkgs allPackages is to drop the scrub
  # pin in favor of a naturally clean build.
  gcc-illumos = auditClosure "gcc-illumos" [
    pkgs.gcc-illumos
    pkgs.gcc-illumos.lib
  ];

  # The full closure that goes into the bootstrap-tools tarball.
  # Building this clean is the precondition for the tarball working on
  # zones without /opt/local. Empirical test: extract the tarball with
  # /opt/local moved aside and run bash + gcc compile-and-link (see
  # ./test-bootstrap-tarball.sh).
  bootstrap-tools = auditClosure "bootstrap-tools" bootstrapToolsPkgs;
}
