{
  inputs = {
    # needs proot 5.3.0 that fixes crashes
    nixpkgs.url = github:NixOS/nixpkgs;
    flake-utils.url = github:numtide/flake-utils;
    home-manager.url = github:nix-community/home-manager;
  };

  outputs = { self, nixpkgs, flake-utils, home-manager, ... }:
    flake-utils.lib.eachDefaultSystem (system: rec {
      lib = { target ? null } @ args: import ./. ({
        inherit target system nixpkgs home-manager;
      } // args);

      packages = rec {
        home-manager-shell = lib {};
        default = home-manager-shell;
      };
      defaultPackage = packages.home-manager-shell;

      apps = rec {
        home-manager-shell = flake-utils.lib.mkApp {
          drv = packages.home-manager-shell;
        };
        default = home-manager-shell;
      };
      defaultApp = apps.home-manager-shell;
    });
}
