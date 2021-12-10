{ lib, buildBazelPackage, fetchFromGitHub, bash }:

buildBazelPackage rec {
  pname = "kubevirt";
  version = "0.41.0";
  commit = "b7f322409e310ebaf7edb9f657d9864ad5730ab0";

  src = fetchFromGitHub {
    owner = pname;
    repo = pname;
    rev = "v${version}";
    sha256 = "033xh8clijxj93avi6qkwfx2756ac5aqrr4hsmh1pgnp9ihxk0wx";
  };

  bazelTarget = ":build-virtctl";

  meta = with lib; {
    description = "A virtual machine management add-on for Kubernetes";
    homepage = "https://github.com/kubevirt/kubevirt";
    maintainers = with maintainers; [ nshalman ];
    license = licenses.asl20;
  };
}
