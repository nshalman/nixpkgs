{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "score-compose";
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "score-spec";
    repo = pname;
    rev = "${version}";
    hash = "sha256-Q0txqnvd7iMLRONTf0GGiHSYSmSYxoTsKJbrrxyyzfg=";
  };

  vendorHash = "sha256-x9Y/WCE8RaytSQMc0jVsyE/pcmAGRLgKBt6jKPDwpyg=";

  meta = with lib; {
    description = "Convert score-spec to docker-compose";
    homepage    = "https://score.dev/";
    license     = licenses.asl20;
    maintainers = [ maintainers.nshalman ];
  };
}
