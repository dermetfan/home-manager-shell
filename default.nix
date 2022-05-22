{ target, system, nixpkgs, home-manager }:

let
  pkgs = nixpkgs.legacyPackages.${system};
  inherit (nixpkgs) lib;

  launch = pkgs.writeShellApplication {
    name = "home-manager-shell-launch";
    runtimeInputs = [ nixpkgs.legacyPackages.${system}.proot ];
    text = ''
      set -x

      activationPackage="$1"
      shift

      TEMPDIR=$(mktemp -d)
      trap 'rm -rf "$TEMPDIR"' EXIT

      mkdir -p "$TEMPDIR"/{profile,home}

      proot \
        -R / \
        -b "$TEMPDIR"/profile:/nix/var/nix/profiles/per-user/"$USER" \
        -b "$TEMPDIR"/home:"$HOME" \
        -w "$HOME" \
        "$activationPackage"/activate

      declare -a prootArgs
      while read -r; do
        prootArgs+=(-b "$REPLY":"$HOME"/"''${REPLY#"$TEMPDIR"/home/}")
      done < <(find "$TEMPDIR"/home -not -type d)

      function launch {
        proot \
          -R / \
          -w "$PWD" \
          "''${prootArgs[@]}" \
          "$@"
      }

      if [[ -n $* ]]; then
        launch "$@"
      elif [[ -n "$SHELL" ]]; then
        launch "$SHELL"
      else
        launch
      fi
    '';
  };
in

pkgs.writeShellApplication {
  name = "home-manager-shell";
  runtimeInputs = [ launch pkgs.jq ];
  text = ''
    set -x

    declare -a enable imports config args

    while getopts :e:i:c:a:p:l: opt; do
      case "$opt" in
        e) enable+=("$OPTARG.enable = true;"$'\n') ;;
        i) imports+=("$OPTARG"$'\n') ;;
        c) config+=("$OPTARG;"$'\n') ;;
        a) args+=("$OPTARG;"$'\n') ;;
        p) nixpkgs="$OPTARG" ;;
        l) homeManager="$OPTARG" ;;
        *) >&2 echo 'Unknown flag'; exit 1 ;;
      esac
    done
    shift $((OPTIND - 1))

    if [[ -z "''${nixpkgs:-}" ]]; then
      nixpkgs=${lib.escapeShellArg nixpkgs}
    fi

    if [[ -z "''${homeManager:-}" ]]; then
      homeManager=${lib.escapeShellArg home-manager}
    fi
  '' + (if target != null then ''
    target=${lib.escapeShellArg target}
  '' else ''
    target="$1"
    shift
  '') + ''
    activationPackage=$(
      #shellcheck disable=SC2016
      nix build activationPackage --json --impure \
        --argstr system ${lib.escapeShellArg system} \
        --argstr nixpkgsFlake "$nixpkgs" \
        --argstr homeManagerFlake "$homeManager" \
        --argstr target "$target" \
        --expr '
          { target, system, nixpkgsFlake, homeManagerFlake }:
          let
            self = __getFlake target;
            nixpkgs = __getFlake nixpkgsFlake;
            home-manager = __getFlake homeManagerFlake;
          in
          home-manager.lib.homeManagerConfiguration rec {
            username = __getEnv "USER";
            homeDirectory = __getEnv "HOME";

            inherit system;
            pkgs = nixpkgs.outputs.legacyPackages.''${system};

            extraSpecialArgs = { inherit self; };

            configuration = { self, config, lib, pkgs, ... }: rec {
              imports = [ '"''${imports[*]}"' ] ++
                lib.optional
                  (self.outputs.homeManagerProfiles.''${username} or null != null)
                  self.outputs.homeManagerProfiles.''${username};

              systemd.user.startServices = lib.mkForce false;

              '"''${enable[*]}"'

              '"''${config[*]}"'
            };

            '"''${args[*]}"'
          }
        ' \
      | jq -r '.[].outputs.out'
    )

    exec homeManagerShell-launch "$activationPackage" "$@"
  '';
}
