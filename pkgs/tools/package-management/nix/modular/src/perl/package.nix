{
  lib,
  stdenv,
  mkMesonDerivation,
  pkg-config,
  perl,
  perlPackages,
  nix-store,
  version,
  curl,
  bzip2,
  libsodium,
}:

perl.pkgs.toPerlModule (
  mkMesonDerivation (finalAttrs: {
    pname = "nix-perl";
    inherit version;

    workDir = ./.;

    nativeBuildInputs = [
      pkg-config
      perl
      curl
    ];

    buildInputs = [
      nix-store
      bzip2
      libsodium
    ];

    # `perlPackages.Test2Harness` is marked broken for Darwin.
    # On illumos patchShebangs leaves Test2Harness' /bin/yath script
    # unrunnable (we already skip Test2Harness' own checkPhase) and
    # meson's test driver dies with OSError: Exec format error trying
    # to exec it.
    doCheck = !stdenv.isDarwin && !stdenv.hostPlatform.isIllumos;

    nativeCheckInputs = [
      perlPackages.Test2Harness
    ];

    preConfigure =
      # "Inline" .version so its not a symlink, and includes the suffix
      ''
        chmod u+w .version
        echo ${finalAttrs.version} > .version
      '';

    mesonFlags = [
      (lib.mesonOption "dbi_path" "${perlPackages.DBI}/${perl.libPrefix}")
      (lib.mesonOption "dbd_sqlite_path" "${perlPackages.DBDSQLite}/${perl.libPrefix}")
      (lib.mesonEnable "tests" finalAttrs.finalPackage.doCheck)
    ];

    mesonCheckFlags = [
      "--print-errorlogs"
    ];

    strictDeps = false;
  })
)
