{ lib, stdenv
, fetchFromGitHub
, installShellFiles
, libuuid
, lvm2_dmeventd  # <libdevmapper-event.h>
, zlib
, python3
}:

stdenv.mkDerivation rec {
  pname = "vdo";
  version = "8.1.1.360";  # kvdo uses this!

  src = fetchFromGitHub {
    owner = "dm-vdo";
    repo = pname;
    rev = version;
    sha256 = "1zp8aaw0diramnlx5z96jcpbm6x0r204xf1vwq6k21rzcazczkwv";
  };

  nativeBuildInputs = [
    installShellFiles
  ];

  buildInputs = [
    libuuid
    lvm2_dmeventd
    zlib
    python3.pkgs.wrapPython
  ];

  propagatedBuildInputs = with python3.pkgs; [
    pyyaml
  ];

  pythonPath = propagatedBuildInputs;

  makeFlags = [
    "DESTDIR=${placeholder "out"}"
    "INSTALLOWNER="
    # all of these paths are relative to DESTDIR and have defaults that don't work for us
    "bindir=/bin"
    "defaultdocdir=/share/doc"
    "mandir=/share/man"
    "python3_sitelib=${python3.sitePackages}"
  ];

  enableParallelBuilding = true;

  postInstall = ''
    installShellCompletion --bash $out/bash_completion.d/*
    rm -r $out/bash_completion.d

    wrapPythonPrograms
  '';

  meta = with lib; {
    homepage = "https://github.com/dm-vdo/vdo";
    description = "A set of userspace tools for managing pools of deduplicated and/or compressed block storage";
    platforms = platforms.linux;
    license = with licenses; [ gpl2Plus ];
    maintainers = with maintainers; [ ajs124 ];
  };
}
