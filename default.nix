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
    sha256 = "4f5379796280cdaeb0c2f358fd04b6a16cc4fb7dfa83b5a8c91a9d963b435231";
    dropPatches = [
      "configure-emulator"
    ];
    # Libraries to build from Node's bundled copy (deps/ in the source)
    # instead of nixpkgs' shared one, when nixpkgs' version is too old.
    # 24.22.1 needs a newer libuv than the pinned nixpkgs has.
    bundledDeps = [
      "libuv"
    ];
  };

  # nodejs_24 and nodejs-slim_24 (without npm) are separate packages built
  # from the same source, so both are bumped.
  targets = {
    nodejs_24 = node24;
    nodejs-slim_24 = node24;
  };

  bump =
    name:
    {
      version,
      sha256,
      dropPatches ? [ ],
      bundledDeps ? [ ],
    }:
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
        patches = builtins.filter (
          patch: !(builtins.any (drop: lib.hasInfix drop (toString patch)) dropPatches)
        ) (old.patches or [ ]);
        # Drop --shared-<dep>, --shared-<dep>-includes=… and
        # --shared-<dep>-libpath=…, so configure uses the bundled copy.
        configureFlags = builtins.filter (
          flag:
          !(builtins.any (
            dep: lib.hasPrefix "--shared-${dep}" (toString flag)
          ) bundledDeps)
        ) (old.configureFlags or [ ]);
        # Keep nixpkgs' headers of those libraries out of the include path.
        buildInputs = builtins.filter (
          input: !(builtins.elem (input.pname or "") bundledDeps)
        ) (old.buildInputs or [ ]);
      })
    else
      lib.warn "nodejs overlay: nixpkgs ${name} is already ${orig.version} (>= ${version}); remove this override" orig;
in
# Each package is only evaluated if the build uses it.
builtins.mapAttrs bump targets
