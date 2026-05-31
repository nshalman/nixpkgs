# Single source of truth for storePath pins used across the illumos-
# recipe. Each entry sidesteps an eval-ordering problem (the pinned
# derivation needs the package set to build, but is consumed before
# the package set fully exists). Consumers `import ./pins.nix` and
# pick the field they need.
#
# Updating any pin: rebuild the corresponding derivation in a working
# builder zone (see comments per-entry for the exact nix-build
# invocation), then edit the path here.
{
  # gcc-illumos.out with proto-strap byte refs scrubbed. Built by
  #   nix-build -E 'with import ./. {}; \
  #     callPackage pkgs/development/compilers/gcc-illumos-scrub {}'
  # Consumed by:
  #   - strap-tools.nix (as the gccIllumos `out` for stage 0)
  #   - default.nix stage 2 (faked into a multi-output gcc-illumos)
  #   - make-bootstrap-tools.nix (as gcc-illumos-scrubbed root)
  gccIllumosScrub =
    builtins.storePath /nix/store/bzvb3ps82ha7aynf3l38ax77m6q257n3-gcc-illumos-scrubbed;

  # GNU binutils 2.44 built clean (no /opt/local in DT_RUNPATH) via
  # the stage-1 stdenv. Replaces proto-strap's polluted binutils in
  # strap-tools' bin/ tree. Rebuild via
  #   nix-build -E 'with import ./. {}; binutils-unwrapped' --no-out-link
  # Consumed by:
  #   - strap-tools.nix (as binutilsIllumos in stage 0)
  #   - make-bootstrap-tools.nix (as a closure root in the tarball)
  binutilsIllumos =
    builtins.storePath /nix/store/chjhxnwkp22s1nr2x9w8wdmmi1w9f0w7-binutils-2.44;

  # patchelf 0.15.2 built via the recipe's stage-2 stdenv. The pinned
  # binary is consumed by patchelf-pin.nix to register the
  # fixupOutputHook for stages 0/1 (stage 2 uses prevStage.patchelf
  # directly). Runtime closure is just gcc-illumos-14.2.0-il-1-lib —
  # zero strap-tools refs.
  #
  # Rebuild via:
  #   1) Set patchelf = null (escape hatch — patchelf-pin.nix returns
  #      null in that case and default.nix's makeStdenv drops it from
  #      extraNativeBuildInputs, breaking the chicken-and-egg).
  #   2) nix-build -E '(import ./. { localSystem = "x86_64-illumos"; }).patchelf' \
  #        --out-link result-patchelf
  #   3) Paste the resulting store path back here.
  patchelf =
    builtins.storePath /nix/store/99mflhrjwf6bdlaayvmvyxfigjqkpcd5-patchelf-0.15.2;
}
