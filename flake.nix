{
  inputs = {
    # needs proot 5.3.0 that fixes crashes
    nixpkgs.url = github:NixOS/nixpkgs/release-22.05;
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
  }: let
    commonPlatforms = with nixpkgs.lib;
      flip pipe [
        (map (p: p.meta.platforms))
        (pp: builtins.foldl' intersectLists (head pp) (tail pp))
      ];
  in
    flake-utils.lib.eachSystem
    (
      # Hard-coding the system is ok here because
      # we only evaluate the `meta.platforms` attribute.
      with nixpkgs.legacyPackages.x86_64-linux;
        commonPlatforms [
          proot

          shellcheck
          # shellcheck advertises platforms
          # that it does not actually support
          # because its dependencies don't
          ghc
        ]
    )
    (system: let
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
          export USER=nobody
          export HOME="$PWD/home/$USER"
          mkdir -p "$HOME"

          user=foo
          home="$PWD/home/$user"
          mkdir "$home"

          cp -r ${self} src
          cd src
          chmod -R +w .
          export home_manager_shell="$PWD"

          cd example

          substituteAllInPlace flake.nix

          nix run .#home-manager-shell --no-write-lock-file -- \
            -U "$user" -H "$home" \
            -i '{ home.file.user.text = config.home.username; }' \
            -i '{ home.file.home.text = config.home.homeDirectory; }' \
            bash -c '
              HOME="'"$home"'"

              cat ~/user; echo
              cat ~/home; echo
              cat ~/.config/bat/config
            ' \
          | tee actual

          cat > expected <<EOF
          $user
          $home
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
