{
  inputs = {
    # needs proot 5.3.0 that fixes crashes
    nixpkgs.url = github:NixOS/nixpkgs;
    flake-utils.url = github:numtide/flake-utils;
    home-manager = {
      url = github:nix-community/home-manager;
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    home-manager,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in rec {
      packages = rec {
        home-manager-shell = self.outputs.lib {inherit system;};
        default = home-manager-shell;
      };
      defaultPackage = packages.default;

      formatter = pkgs.alejandra;

      checks.example =
        pkgs.runCommandNoCC "example" {
          __impure = true;
          nativeBuildInputs = with pkgs; [nix cacert diffutils];
          requiredSystemFeatures = ["recursive-nix"];
          NIX_CONFIG = ''
            extra-experimental-features = nix-command flakes
          '';
        } ''
          mkdir home
          export HOME="$PWD/home"
          export USER=nobody

          cp -r ${self} src
          cd src
          chmod -R +w .
          export home_manager_shell="$PWD"

          cd example

          substituteAllInPlace flake.nix

          nix run .#home-manager-shell --no-write-lock-file -- \
            -i '{ home.file.test.text = "test"; }' \
            cat \
              ~/test <(echo) \
              ~/.config/bat/config \
          | tee actual

          cat > expected <<EOF
          test
          --style='numbers'
          EOF

          if [[ "$(< actual)" != "$(< expected)" ]]; then
            diff --suppress-common-lines expected actual
            exit 1
          fi

          touch $out
        '';
    })
    // {
      lib = {self ? null, ...} @ args:
        import ./. ({inherit self nixpkgs home-manager;} // args);
    };
}
