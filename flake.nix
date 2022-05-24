{
  inputs = {
    # needs proot 5.3.0 that fixes crashes
    nixpkgs.url = github:NixOS/nixpkgs;
    flake-utils.url = github:numtide/flake-utils;
    home-manager.url = github:nix-community/home-manager;
  };

  outputs = { self, nixpkgs, flake-utils, home-manager, ... }:
    flake-utils.lib.eachDefaultSystem (system: rec {
      packages = rec {
        home-manager-shell = self.outputs.lib { inherit system; };
        default = home-manager-shell;
      };
      defaultPackage = packages.default;

      apps = rec {
        home-manager-shell = flake-utils.lib.mkApp {
          drv = packages.home-manager-shell;
        };
        default = home-manager-shell;
      };
      defaultApp = apps.default;
    }) // {
      lib = { self ? null, ... } @ args: import ./. ({
        inherit self nixpkgs home-manager;
      } // args);
    };
}
