# Node.js version-bump overlay, used by Nixpacks/Coolify via `nixOverlays`.
#
# Installs the official prebuilt binary from nodejs.org instead of compiling
# from source. For each platform you deploy on, put the SHA-256 of
# node-v<version>-linux-<arch>.tar.xz from
# https://nodejs.org/dist/v<version>/SHASUMS256.txt (hex is fine).
final: prev:

let
  # From prev, not final: using final.lib to build this overlay's attribute
  # set makes the package-set fixpoint depend on itself.
  inherit (prev) lib;

  node24 = {
    version = "24.22.1";
    sha256 = {
      x86_64-linux = "6c172a9ab6718f7b801fb5a7bd486af2ee5e32758086a04b84fcce2aa77095e6";
    };
  };

  # nodejs_24 and nodejs-slim_24 (without npm) both point to the binary
  # release, which includes npm and corepack.
  targets = {
    nodejs_24 = node24;
    nodejs-slim_24 = node24;
  };

  archOf = {
    x86_64-linux = "x64";
    aarch64-linux = "arm64";
  };

  nodeBinary =
    { version, sha256 }:
    let
      system = final.stdenv.hostPlatform.system;
      arch = archOf.${system} or (throw "nodejs overlay: no Node.js binary for ${system}");
      hash =
        sha256.${system} or (throw "nodejs overlay: no sha256 for ${system} in the overlay; add it from SHASUMS256.txt");
    in
    final.stdenv.mkDerivation {
      pname = "nodejs";
      inherit version;

      src = final.fetchurl {
        url = "https://nodejs.org/dist/v${version}/node-v${version}-linux-${arch}.tar.xz";
        sha256 = hash;
      };

      # Points the binary at Nix's dynamic loader, libstdc++ and libgcc_s.
      nativeBuildInputs = [ final.autoPatchelfHook ];
      buildInputs = [ final.stdenv.cc.cc.lib ];

      dontConfigure = true;
      dontBuild = true;
      # npm, npx and corepack use `#!/usr/bin/env node`, which works as-is
      # in the Nixpacks image once node is on PATH.
      dontPatchShebangs = true;

      installPhase = ''
        runHook preInstall
        mkdir -p $out
        cp -r bin include lib share $out/
        runHook postInstall
      '';

      meta = {
        description = "Node.js ${version} (official prebuilt binary)";
        mainProgram = "node";
        platforms = builtins.attrNames sha256;
      };
    };

  bump =
    name:
    spec:
    let
      orig =
        prev.${name}
          or (throw "nodejs overlay: ${name} does not exist in this nixpkgs revision; cannot bump to ${spec.version}");
    in
    # Never downgrade: once nixpkgs has caught up (or passed) this version,
    # the overlay becomes a no-op and prints a reminder to remove it.
    if lib.versionOlder orig.version spec.version then
      nodeBinary spec
    else
      lib.warn "nodejs overlay: nixpkgs ${name} is already ${orig.version} (>= ${spec.version}); remove this override" orig;
in
# Each package is only evaluated if the build uses it.
builtins.mapAttrs bump targets
