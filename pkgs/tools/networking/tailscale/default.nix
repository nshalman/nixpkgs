{ stdenv, lib, fetchurl, dpkg }:

stdenv.mkDerivation rec {
  pname = "tailscale-relay";
  version = "0.94-85";

  src = fetchurl {
    url = "https://tailscale.com/files/dist/${pname}_${version}_amd64.deb";
    sha256 = "1xl2h5dc2jlycbvh2pkyqrssf0vwvvhrm7cg2ib3pz1whiyxf1j7";
  };

  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ dpkg ];

  unpackPhase = "dpkg-deb --fsys-tarfile $src | tar -x --no-same-permissions --no-same-owner";

  installPhase = ''
      mkdir -p $out
      cp -R usr/sbin $out/bin
      for file in $out/bin/taillogin $out/bin/relaynode; do
        chmod +w $file
        patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
                 $file
      done
      cp -R usr/share $out
      cp -R etc $out/etc
      cp -R lib $out/lib

      substituteInPlace $out/lib/systemd/system/tailscale-relay.service \
        --replace "/usr/sbin/" "$out/bin/"
  '';

  postInstall = ''
  '';

  meta = with stdenv.lib; {
    homepage = "https://tailscale.com/";
    description = "Create a private, encrypted mesh network between your computers, without proxies or intermediaries.";
    longDescription = ''
      Connect your devices and services, wherever they are.
      Tailscale creates a private, encrypted mesh network between your computers,
      without proxies or intermediaries.
    '';
    license = licenses.unfree;
    maintainers = with maintainers; [ nshalman ];
    platforms = [ "x86_64-linux" ];
  };
}
