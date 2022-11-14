{ flutter
, lib
, llvmPackages_13
, cmake
, ninja
, pkg-config
, wrapGAppsHook
, autoPatchelfHook
, util-linux
, libselinux
, libsepol
, libthai
, libdatrie
, libxkbcommon
, at-spi2-core
, libsecret
, jsoncpp
, xorg
, dbus
, gtk3
, glib
, pcre
, libepoxy
, stdenvNoCC
, cacert
, git
, dart
, nukeReferences
, targetPlatform
, bash
, curl
, unzip
, which
, xz
}:

# absolutely no mac support for now

args:
let
  pl = n: "##FLUTTER_${n}_PLACEHOLDER_MARKER##";
  placeholder_deps = pl "DEPS";
  placeholder_flutter = pl "FLUTTER";
  fetchAttrs = [ "src" "sourceRoot" "setSourceRoot" "unpackPhase" "patches" ];
  getAttrsOrNull = names: attrs: lib.genAttrs names (name: if attrs ? ${name} then attrs.${name} else null);
  flutterDeps = [
    # flutter deps
    flutter.wrapped
    bash
    curl
    flutter.dart
    git
    unzip
    which
    xz
  ];
  self =
(self: llvmPackages_13.stdenv.mkDerivation (args // {
  deps = stdenvNoCC.mkDerivation (lib.recursiveUpdate (getAttrsOrNull fetchAttrs args) {
    name = "${self.name}-deps-flutter-v${flutter.unwrapped.version}-${targetPlatform.system}.tar.gz";

    nativeBuildInputs = flutterDeps ++ [
      nukeReferences
    ];

    # avoid pub phase
    dontBuild = true;

    installPhase = ''
      . ${../fetchgit/deterministic-git}

      TMP=$(mktemp -d)

      export HOME="$TMP"
      export PUB_CACHE=''${PUB_CACHE:-"$HOME/.pub-cache"}
      export ANDROID_EMULATOR_USE_SYSTEM_LIBS=1

      flutter config --no-analytics &>/dev/null # mute first-run
      flutter config --enable-linux-desktop
      flutter packages get
      flutter build linux || true # so it downloads tools
      ${lib.optionalString (args ? flutterExtraFetchCommands) args.flutterExtraFetchCommands}

      RES="$TMP"

      mkdir -p "$RES/f"

      # so we can use lock, diff yaml
      cp "pubspec.yaml" "$RES"
      cp "pubspec.lock" "$RES"
      mv .dart_tool .flutter-plugins .flutter-plugins-dependencies "$RES/f"

      # replace paths with placeholders
      find "$RES" -type f -exec sed -i \
        -e s,$TMP,${placeholder_deps},g \
        -e s,${flutter.unwrapped},${placeholder_flutter},g \
        {} +

      remove_line_matching() {
        replace_line_matching "$1" "$2" ""
      }

      replace_line_matching() {
        sed "s|.*$2.*|$3|g" -r -i "$1"
      }

      # nuke nondeterminism

      # clientId is random
      remove_line_matching "$RES/.flutter" clientId

      # deterministic git repos
      find "$RES" -iname .git -type d | while read -r repoGit; do
        make_deterministic_repo "$(dirname "$repoGit")"
      done

      # dart _fetchedAt, etc
      DART_DATE=$(date --date="@$SOURCE_DATE_EPOCH" -In | sed "s|,|.|g" | sed "s|+.*||g")
      find "$RES/.pub-cache" -iname "*.json" -exec sed -r 's|.*_fetchedAt.*|    "_fetchedAt": "'"$DART_DATE"'",|g' -i {} +
      replace_line_matching "$RES/f/.dart_tool/package_config.json" '"generated"' '"generated": "'"$DART_DATE"'",'
      replace_line_matching "$RES/f/.flutter-plugins-dependencies" '"date_created"' '"date_created": "'"$DART_DATE"'",'

      # nuke refs
      find "$RES" -type f -exec nuke-refs {} +

      # Build a reproducible tar, per instructions at https://reproducible-builds.org/docs/archives/
      tar --owner=0 --group=0 --numeric-owner --format=gnu \
          --sort=name --mtime="@$SOURCE_DATE_EPOCH" \
          -czf "$out" -C "$RES" .
    '';

    GIT_SSL_CAINFO = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";

    impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [
      "GIT_PROXY_COMMAND" "NIX_GIT_SSL_CAINFO" "SOCKS_SERVER"
    ];

    # unnecesarry
    dontFixup = true;

    outputHashAlgo = if self ? vendorHash then null else "sha256";
    # outputHashMode = "recursive";
    outputHash = if self ? vendorHash then
      self.vendorHash
    else if self ? vendorSha256 then
      self.vendorSha256
    else
      lib.fakeSha256;

  });

  nativeBuildInputs = flutterDeps ++ [
    # flutter dev tools
    cmake
    ninja
    pkg-config
    wrapGAppsHook
    # flutter likes dynamic linking
    autoPatchelfHook
  ] ++ lib.optionals (args ? nativeBuildInputs) args.nativeBuildInputs;

  buildInputs = [
    # cmake deps
    gtk3
    glib
    pcre
    util-linux
    # also required by cmake, not sure if really needed or dep of all packages
    libselinux
    libsepol
    libthai
    libdatrie
    xorg.libXdmcp
    xorg.libXtst
    libxkbcommon
    dbus
    at-spi2-core
    libsecret
    jsoncpp
    # build deps
    xorg.libX11
    # directly required by build
    libepoxy
  ] ++ lib.optionals (args ? buildInputs) args.buildInputs;

  # TODO: do we need this?
  NIX_LDFLAGS = "-rpath ${lib.makeLibraryPath self.buildInputs}";
  NIX_CFLAGS_COMPILE = "-I${xorg.libX11}/include";
  LD_LIBRARY_PATH = lib.makeLibraryPath self.buildInputs;

  configurePhase = ''
    runHook preConfigure

    # for some reason fluffychat build breaks without this - seems file gets overriden by some tool
    cp pubspec.yaml pubspec-backup

    # we get this from $depsFolder so disabled for now, but we might need it again once deps are fetched properly
    # flutter config --no-analytics >/dev/null 2>/dev/null # mute first-run
    # flutter config --enable-linux-desktop

    # extract deps
    depsFolder=$(mktemp -d)
    tar xzf "$deps" -C "$depsFolder"

    # after extracting update paths to point to real paths
    find "$depsFolder" -type f -exec sed -i \
      -e s,${placeholder_deps},$depsFolder,g \
      -e s,${placeholder_flutter},${flutter.unwrapped},g \
      {} +

    # ensure we're using a lockfile for the right package version
    if [ -e pubspec.lock ]; then
      # FIXME: currently this is broken. in theory this should not break, but flutter has it's own way of doing things.
      # diff -u pubspec.lock $depsFolder/pubspec.lock
      true
    else
      cp -v "$depsFolder/pubspec.lock" .
    fi
    diff -u pubspec.yaml $depsFolder/pubspec.yaml

    mv -v $(find $depsFolder/f -type f) .

    # prepare
    export HOME=$depsFolder
    export PUB_CACHE=''${PUB_CACHE:-"$HOME/.pub-cache"}
    export ANDROID_EMULATOR_USE_SYSTEM_LIBS=1

    # binaries need to be patched
    autoPatchelf -- "$depsFolder"

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    # for some reason fluffychat build breaks without this - seems file gets overriden by some tool
    mv pubspec-backup pubspec.yaml
    mkdir -p build/flutter_assets/fonts

    flutter packages get --offline -v
    flutter build linux --release -v

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    built=build/linux/*/release/bundle

    mkdir -p $out/bin
    mv $built $out/app

    for f in $(find $out/app -iname "*.desktop" -type f); do
      install -D $f $out/share/applications/$(basename $f)
    done

    for f in $(find $out/app -maxdepth 1 -type f); do
      ln -s $f $out/bin/$(basename $f)
    done

    # this confuses autopatchelf hook otherwise
    rm -rf "$depsFolder"

    # make *.so executable
    find $out/app -iname "*.so" -type f -exec chmod +x {} +

    # remove stuff like /build/source/packages/ubuntu_desktop_installer/linux/flutter/ephemeral
    for f in $(find $out/app -executable -type f); do
      if patchelf --print-rpath "$f" | grep /build; then # this ignores static libs (e,g. libapp.so) also
        echo "strip RPath of $f"
        newrp=$(patchelf --print-rpath $f | sed -r "s|/build.*ephemeral:||g" | sed -r "s|/build.*profile:||g")
        patchelf --set-rpath "$newrp" "$f"
      fi
    done

    runHook postInstall
  '';
})) self;
in
  self
