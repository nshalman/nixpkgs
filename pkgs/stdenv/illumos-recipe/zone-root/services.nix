# Declarative SMF service list for the nix zone — the single source of
# truth for services shipped in the zone image. Consumed by:
#
#   - make-zone-root.nix / zone-root/builder.sh: every manifest in
#     `bundle` is svccfg-imported into the image's repository.db at
#     zone-root build time, so the services exist from first boot.
#   - zone-root/system.nix: `bundle` is folded into the system profile,
#     so the manifests are also visible in-zone at
#     /nix/var/nix/profiles/default/lib/svc/manifest/site/ (input for
#     the future import-on-rebuild activation step, bd nix-whz).
#
# To add a service: define it with smf-lib's mkSmfManifest (and
# mkSmfMethodScript if it needs tailscale-style start/stop logic), add
# it to `manifests`, rebuild. Test with ../test-smf-lib.sh.
{
  pkgs ? import ../../../.. { },
}:
let
  smf = import ../smf-lib.nix { inherit pkgs; };
in
rec {
  # The nix-daemon socket server: exposes
  # /nix/var/nix/daemon-socket/socket and serves build requests from
  # clients (root or unprivileged) running NIX_REMOTE=daemon.
  nix-daemon = smf.mkSmfManifest {
    name = "nix-daemon";
    description = "Nix build daemon";
    documentation = {
      name = "nix-daemon manual";
      uri = "https://nix.dev/manual/nix/stable/command-ref/nix-daemon";
    };
    start = {
      exec = "/nix/var/nix/profiles/default/bin/nix-daemon";
      timeout = 60;
      user = "root";
      group = "root";
    };
    # 'child' so SMF tracks the long-running nix-daemon process
    # directly; the daemon does not double-fork. ignore_error so a
    # single crash doesn't fall into maintenance while we're still
    # shaking out illumos portability issues (peer-cred, etc.).
    duration = "child";
    ignoreError = "core,signal";
  };

  manifests = [ nix-daemon ];

  bundle = smf.mkSmfManifestBundle { inherit manifests; };
}
