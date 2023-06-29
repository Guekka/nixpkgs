{ autoconf
, automake
, bash
, cacert
, cmake
, cmakerc
, coreutils
, curl
, fetchFromGitHub
, fmt
, gcc
, git
, gnumake
, gzip
, jq
, lib
, makeWrapper
, meson
, ninja
, perl
, pkg-config
, python3
, runtimeShell
, stdenv
, zip
, zstd
}:
let
  # These are the most common binaries used by vcpkg
  # If a port requires a binary that is not in this list,
  # it can be added by an overlay
  runtimeDeps = [
    autoconf
    automake
    bash
    cacert
    coreutils
    curl
    cmake
    gcc
    git
    gnumake
    gzip
    meson
    ninja
    perl
    pkg-config
    python3
    zip
    zstd
  ];
in
stdenv.mkDerivation rec {
  pname = "vcpkg";
  version = "2023-06-22";

  src = fetchFromGitHub {
    owner = "microsoft";
    repo = "vcpkg-tool";
    rev = "2023-06-22";
    hash = "sha256-/Bn2TW6JWU676NzsQdtC6G513MtRHblLVP0pK5jyCWc=";
  };

  vcpkg_data = fetchFromGitHub {
    owner = "microsoft";
    repo = "vcpkg";
    rev = "2023.06.20";
    hash = "sha256-unzfRq1sOVxgRlBCqh+Ig9eL9A9O9W0YCAPVYJvDOq4=";
  };

  nativeBuildInputs = [
    cmake
    cmakerc
    fmt
    makeWrapper
  ];

  cmakeFlags = [
    "-DVCPKG_DEPENDENCY_EXTERNAL_FMT=ON"
    "-DVCPKG_DEPENDENCY_CMAKERC=ON"
  ];

  # vcpkg needs to be able to write to VCPKG_ROOT, and requires the executable to be in VCPKG_ROOT
  # One way to achieve that would be to write a nixos module, but it would be better to be able to
  # use vcpkg in a nix-shell
  # So here's a wrapper script that will use the current user's home directory to store vcpgk's data
  # Note: we cannot use writeShellScript, because the placeholder would refer to the script itself
  vcpkgScript =
    let
      out = placeholder "out";
    in
    ''
      #!${runtimeShell}

      # make one root directory per vcpkg version
      vcpkg_hash=$(echo -n "${out}" | sha256sum | cut -f1 -d ' ')
      vcpkg_root_path="$HOME/.local/vcpkg/roots/$vcpkg_hash"

      # create the root directory if it doesn't exist, and create symlinks to the vcpkg data
      if [[ ! -d $vcpkg_root_path ]]; then
        mkdir -p $vcpkg_root_path

        ln -s ${out}/share/vcpkg/{docs,ports,scripts,triplets,versions,LICENSE.txt} $vcpkg_root_path/
        ln -s ${out}/bin/vcpkg $vcpkg_root_path/

        # this file is used as a lock by vcpkg, so it needs to be writable
        touch $vcpkg_root_path/.vcpkg-root
      fi

      # add a special flag to tell the user where the root is. This can be used by nix-shell for
      # finding the cmake toolchain file
      if [[ "$1" == "--root-for-nix-usage" ]]; then
        echo "$vcpkg_root_path"
        exit 0
      fi

      export VCPKG_FORCE_SYSTEM_BINARIES=1
      export VCPKG_ROOT="$vcpkg_root_path"
      export VCPKG_DOWNLOADS="$vcpkg_root_path/downloads"
      exec ${out}/share/vcpkg/vcpkg "$@"
    '';

  passAsFile = [ "vcpkgScript" ];

  # This list contains the ports that fail to build
  # They are replaced by a dummy port that will tell the user to install them with Nix
  # It is not exhaustive, but can be extended with an overlay
  nativePackages = [
    "gettext"
    "qt"
    "qt5"
  ];

  postInstall = ''
    mkdir -p $out/share/vcpkg

    cp --preserve=mode -r ${vcpkg_data}/{docs,ports,scripts,triplets,versions,LICENSE.txt} $out/share/vcpkg

    # we preserve the original vcpkg binary, and replace it with a wrapper script
    mv $out/bin/vcpkg $out/share/vcpkg/vcpkg
    cp $vcpkgScriptPath $out/bin/vcpkg
    chmod +x $out/bin/vcpkg
  '';

  postFixup = ''
    # instead of fixing all the ports manually, we prompt the user to install them using Nix
    # in the future, a better solution would be to generate a nix derivation from
    # the vcpkg manifest
    for port in ${lib.concatStringsSep " " nativePackages}
    do
      portfile=$out/share/vcpkg/ports/$port/portfile.cmake
      echo 'set(VCPKG_POLICY_EMPTY_PACKAGE enabled)' > $portfile
      echo "message(WARNING Please install $port with Nix)" >> $portfile

      # We're going to manipulate the vcpkg.json here
      # We want to preserve the structure, but remove all dependencies
      manifest=$out/share/vcpkg/ports/$port/vcpkg.json
      ${jq}/bin/jq 'walk(if type == "object" and has("dependencies") then .dependencies = [] else . end)' \
        $manifest > result.json
      mv result.json $manifest
    done

    # add the runtime dependencies to the PATH
    wrapProgram $out/share/vcpkg/vcpkg --set PATH ${lib.makeBinPath runtimeDeps}
  '';

  meta = with lib; {
    description = "C++ Library Manager";
    homepage = "https://vcpkg.io/";
    license = licenses.mit;
    maintainers = with maintainers; [ guekka ];
  };
}
