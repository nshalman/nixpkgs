{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.tailscale;
in {
  meta.maintainers = [ maintainers.nshalman ];

  ###### interface
  options.services.tailscale = {
    enable = mkEnableOption "tailscale";
    tun = mkOption {
     type = types.str;
     default = "wg0";
     example = "wg0";
     description = "Name of the tun device Tailscale should use";
   };
  };

  ###### implementation
  config = mkIf cfg.enable {
    systemd.services.tailscale = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      description = "Traffic relay node for Tailscale IPN";
      serviceConfig = {
        EnvironmentFile = "${pkgs.tailscale}/etc/default/tailscale-relay";
        ConditionPathExists = "/var/lib/tailscale/relay.conf";
        ExecStart = "${pkgs.tailscale}/bin/relaynode --config /var/lib/tailscale/relay.conf --tun=${cfg.tun} $PORT $ACL_FILE $FLAGS";
        Restart = "on-failure";
      };
    };
  };
}
