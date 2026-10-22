# Node.js version-bump overlay, used by Nixpacks/Coolify via `nixOverlays`.
#
# For each package: put the new version and the SHA-256 of
# node-v<version>.tar.xz from https://nodejs.org/dist/v<version>/SHASUMS256.txt
# (hex is fine, fetchurl accepts it as-is).
final: prev:

let
  # From prev, not final: using final.lib to build this overlay's attribute
  # set makes the package-set fixpoint depend on itself.
  inherit (prev) lib;

  node24 = {
    version = "24.22.1";
    sha256 = "6c172a9ab6718f7b801fb5a7bd486af2ee5e32758086a04b84fcce2aa77095e6";
  };

  # nodejs_24 and nodejs-slim_24 (without npm) are separate packages built
  # from the same source, so both are bumped.
  targets = {
    nodejs_24 = node24;
    nodejs-slim_24 = node24;
  };

  bump =
    name:
    { version, sha256 }:
    let
      orig =
        prev.${name}
          or (throw "nodejs overlay: ${name} does not exist in this nixpkgs revision; cannot bump to ${version}");
    in
    # Never downgrade: once nixpkgs has caught up (or passed) this version,
    # the overlay becomes a no-op and prints a reminder to remove it.
    if lib.versionOlder orig.version version then
      orig.overrideAttrs (old: {
        inherit version;
        src = final.fetchurl {
          url = "https://nodejs.org/dist/v${version}/node-v${version}.tar.xz";
          inherit sha256;
        };
      })
    else
      lib.warn "nodejs overlay: nixpkgs ${name} is already ${orig.version} (>= ${version}); remove this override" orig;
in
# Each package is only evaluated if the build uses it.
builtins.mapAttrs bump targets
