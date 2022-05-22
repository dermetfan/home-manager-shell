{
  target, system,
  nixpkgs, home-manager,
  enable ? [],
  imports ? [],
  args ? {},
}:

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

    declare -a enable imports args

    while getopts :e:i:c:a:p:l: opt; do
      case "$opt" in
        e) enable+=("$OPTARG.enable = true;"$'\n') ;;
        i) imports+=("$OPTARG"$'\n') ;;
        a) args+=("$OPTARG;"$'\n') ;;
        p) nixpkgs="$OPTARG" ;;
        l) homeManager="$OPTARG" ;;
        *) >&2 echo 'Unknown flag'; exit 1 ;;
      esac
    done
    shift $((OPTIND - 1))

    enable+=(${lib.escapeShellArgs enable})
    imports+=(${lib.escapeShellArgs imports})

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
    WD="$PWD"
    function cleanup {
      cd "$WD"
      rm -rf "$TEMPDIR"
    }
    trap cleanup EXIT
    TEMPDIR=$(mktemp -d)
    cd "$TEMPDIR"

    vars=$(
      nix-instantiate --eval --strict \
        --argstr system ${lib.escapeShellArg system} \
        --argstr username "$USER" \
        --argstr homeDirectory "$HOME" \
        --argstr args ${lib.escapeShellArg (__toJSON args)} \
        --expr '{ ... } @ args: {
          hmArgs = { inherit (args) system username homeDirectory; };
          args = __fromJSON args.args;
        }'
    )

    cat > flake.nix <<EOF
    {
      inputs = {
        target.url = "$target";
        nixpkgs.url = "$nixpkgs";
        home-manager.url = "$homeManager";
      };

      outputs = { self, target, nixpkgs, home-manager }: let
        inherit ($vars) hmArgs args;
        inherit (hmArgs) system username;
      in {
        packages.\''${system}.homeManagerConfiguration = home-manager.lib.homeManagerConfiguration (
          hmArgs // nixpkgs.lib.recursiveUpdate rec {
            pkgs =
              target.outputs.legacyPackages.\''${system} or
              nixpkgs.outputs.legacyPackages.\''${system};

            extraSpecialArgs.self = target;

            configuration = { self, config, lib, pkgs, ... }: rec {
              imports = [ ''${imports[*]} ] ++
                lib.optional
                  (self.outputs.homeManagerProfiles.\''${username} or null != null)
                  self.outputs.homeManagerProfiles.\''${username};

              systemd.user.startServices = lib.mkForce false;

              ''${enable[*]}
            };

            ''${args[*]}
          } args
        );
      };
    }
    EOF

    nix flake lock

    activationPackage=$(
      nix build .#homeManagerConfiguration.activationPackage --json --impure \
      | jq -r '.[].outputs.out'
    )

    cleanup

    exec home-manager-shell-launch "$activationPackage" "$@"
  '';
}
