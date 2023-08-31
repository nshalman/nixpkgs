{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "score-helm";
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "score-spec";
    repo = pname;
    rev = "${version}";
    hash = "sha256-pnl0M+jDCVb0m0KQnaCwB7cxB4NbAky2V/xhTY7Re/M=";
  };

  vendorHash = "sha256-xPy8vXqcES3JIoJH9BfZ8ODByt0CRbjK5BiNrtmTgnk=";

  meta = with lib; {
    description = "Convert score-spec to helm ";
    homepage    = "https://score.dev/";
    license     = licenses.asl20;
    maintainers = [ maintainers.nshalman ];
  };
}
