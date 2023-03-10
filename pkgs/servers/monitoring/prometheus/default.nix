{ stdenv
, lib
, go
, pkgs
, buildGoModule
, fetchFromGitHub
, fetchurl
, nixosTests
, enableAWS ? true
, enableAzure ? true
, enableConsul ? true
, enableDigitalOcean ? true
, enableDNS ? true
, enableEureka ? true
, enableGCE ? true
, enableHetzner ? true
, enableIONOS ? true
, enableKubernetes ? true
, enableLinode ? true
, enableMarathon ? true
, enableMoby ? true
, enableNomad ? true
, enableOpenstack ? true
, enablePuppetDB ? true
, enableScaleway ? true
, enableTriton ? true
, enableUyuni ? true
, enableVultr ? true
, enableXDS ? true
, enableZookeeper ? true
}:

let
  version = "2.42.0";
  webUiStatic = fetchurl {
    url = "https://github.com/prometheus/prometheus/releases/download/v${version}/prometheus-web-ui-${version}.tar.gz";
    sha256 = "sha256-QOnt8YZkq+/cmoaI8ZOrVbgVh5MnaKpDBVtPTckl4+A=";
  };
in
buildGoModule rec {
  pname = "prometheus";
  inherit version;

  outputs = [ "out" "doc" "cli" ];

  src = fetchFromGitHub {
    owner = "prometheus";
    repo = "prometheus";
    rev = "v${version}";
    sha256 = "sha256-UwowidKKn3fp2z/MSbwESpl2E4IIioEC0oV1QRE7ViQ=";
  };

  vendorSha256 = "sha256-wUniz7E9l/5ldgPHo+wZkKaZuAH5kvjT0VDl4qkcoNs=";

  excludedPackages = [ "documentation/prometheus-mixin" ];

  postPatch = ''
    tar -C web/ui -xzf ${webUiStatic}

    patchShebangs scripts

    # Enable only select service discovery to shrink binaries.
    (
      true # prevent bash syntax error when all plugins are disabled
    ${lib.optionalString enableAWS          "echo - github.com/prometheus/prometheus/discovery/aws"}
    ${lib.optionalString enableAzure        "echo - github.com/prometheus/prometheus/discovery/azure"}
    ${lib.optionalString enableConsul       "echo - github.com/prometheus/prometheus/discovery/consul"}
    ${lib.optionalString enableDigitalOcean "echo - github.com/prometheus/prometheus/discovery/digitalocean"}
    ${lib.optionalString enableDNS          "echo - github.com/prometheus/prometheus/discovery/dns"}
    ${lib.optionalString enableEureka       "echo - github.com/prometheus/prometheus/discovery/eureka"}
    ${lib.optionalString enableGCE          "echo - github.com/prometheus/prometheus/discovery/gce"}
    ${lib.optionalString enableHetzner      "echo - github.com/prometheus/prometheus/discovery/hetzner"}
    ${lib.optionalString enableIONOS        "echo - github.com/prometheus/prometheus/discovery/ionos"}
    ${lib.optionalString enableKubernetes   "echo - github.com/prometheus/prometheus/discovery/kubernetes"}
    ${lib.optionalString enableLinode       "echo - github.com/prometheus/prometheus/discovery/linode"}
    ${lib.optionalString enableMarathon     "echo - github.com/prometheus/prometheus/discovery/marathon"}
    ${lib.optionalString enableMoby         "echo - github.com/prometheus/prometheus/discovery/moby"}
    ${lib.optionalString enableNomad        "echo - github.com/prometheus/prometheus/discovery/nomad"}
    ${lib.optionalString enableOpenstack    "echo - github.com/prometheus/prometheus/discovery/openstack"}
    ${lib.optionalString enablePuppetDB     "echo - github.com/prometheus/prometheus/discovery/puppetdb"}
    ${lib.optionalString enableScaleway     "echo - github.com/prometheus/prometheus/discovery/scaleway"}
    ${lib.optionalString enableTriton       "echo - github.com/prometheus/prometheus/discovery/triton"}
    ${lib.optionalString enableUyuni        "echo - github.com/prometheus/prometheus/discovery/uyuni"}
    ${lib.optionalString enableVultr        "echo - github.com/prometheus/prometheus/discovery/vultr"}
    ${lib.optionalString enableXDS          "echo - github.com/prometheus/prometheus/discovery/xds"}
    ${lib.optionalString enableZookeeper    "echo - github.com/prometheus/prometheus/discovery/zookeeper"}
    ) > plugins.yml
  '';

  preBuild = ''
    if [[ -d vendor ]]; then GOARCH= make -o assets assets-compress plugins; fi
  '';

  tags = [ "builtinassets" ];

  ldflags =
    let
      t = "github.com/prometheus/common/version";
    in
    [
      "-s"
      "-w"
      "-X ${t}.Version=${version}"
      "-X ${t}.Revision=unknown"
      "-X ${t}.Branch=unknown"
      "-X ${t}.BuildUser=nix@nixpkgs"
      "-X ${t}.BuildDate=unknown"
      "-X ${t}.GoVersion=${lib.getVersion go}"
    ];

  preInstall = ''
    mkdir -p "$out/share/doc/prometheus" "$out/etc/prometheus"
    cp -a $src/documentation/* $out/share/doc/prometheus
    cp -a $src/console_libraries $src/consoles $out/etc/prometheus
  '';

  postInstall = ''
    moveToOutput bin/promtool $cli
  '';

  doCheck = !stdenv.isDarwin; # https://hydra.nixos.org/build/130673870/nixlog/1

  passthru.tests = { inherit (nixosTests) prometheus; };

  meta = with lib; {
    description = "Service monitoring system and time series database";
    homepage = "https://prometheus.io";
    license = licenses.asl20;
    maintainers = with maintainers; [ fpletz willibutz Frostman ];
  };
}
