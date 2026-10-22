# Node.js version-bump overlay, used by Nixpacks/Coolify via `nixOverlays`.
#
# Installs the official prebuilt binary from nodejs.org, unmodified, instead
# of compiling from source. For each platform you deploy on, put the SHA-256 of
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
      # aarch64-linux = "<sha256 of node-v24.22.1-linux-arm64.tar.xz>";
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

      # Leave the binary exactly as published: it uses the image's own
      # dynamic loader and system libraries (glibc, libstdc++), so native
      # modules such as Prisma's query engine find system libraries like
      # libssl.so.3 the same way they would with Node installed on Ubuntu.
      # This means the binary runs on regular Linux (the Nixpacks image) but
      # not on NixOS.
      dontConfigure = true;
      dontBuild = true;
      dontPatchELF = true;
      dontStrip = true;
      # npm, npx and corepack use `#!/usr/bin/env node`, which works as-is
      # in the Nixpacks image once node is on PATH.
      dontPatchShebangs = true;

      installPhase = ''
        runHook preInstall
        mkdir -p $out
        cp -r bin include lib share $out/
        runHook postInstall
      '';

      # Newer nixpkgs assembles nodejs_24 from nodejs-slim_24 plus
      # nodejs-slim_24.npm. The binary release already contains npm, so the
      # separate npm part is an empty placeholder.
      passthru.npm = final.emptyDirectory;

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
      # Compare against nodejs-slim_24, which is always built directly. In
      # newer nixpkgs, nodejs_24 takes its version from nodejs-slim_24 as
      # already replaced by this overlay, so its own version can't be trusted.
      nixpkgsVersion = (prev.nodejs-slim_24 or orig).version;
    in
    # Never downgrade: once nixpkgs has caught up (or passed) this version,
    # the overlay becomes a no-op and prints a reminder to remove it.
    if lib.versionOlder nixpkgsVersion spec.version then
      nodeBinary spec
    else
      lib.warn "nodejs overlay: nixpkgs ${name} is already ${nixpkgsVersion} (>= ${spec.version}); remove this override" orig;
in
# Each package is only evaluated if the build uses it.
builtins.mapAttrs bump targets
