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
in

pkgs.writeShellApplication {
  name = "home-manager-shell";
  runtimeInputs = with pkgs; [ proot jq ];
  text = ''
    declare -a enable imports args

    while getopts :e:i:c:a:p:l:bnv opt; do
      case "$opt" in
        e) enable+=("$OPTARG.enable = true;"$'\n') ;;
        i) imports+=("$OPTARG"$'\n') ;;
        a) args+=("$OPTARG;"$'\n') ;;
        p) nixpkgs="$OPTARG" ;;
        l) homeManager="$OPTARG" ;;
        b) bare=1 ;;
        n) dry=1 ;;
        v) verbose=1 ;;
        *) >&2 echo 'Unknown flag'; exit 1 ;;
      esac
    done
    shift $((OPTIND - 1))

    if [[ -n "''${verbose:-}" ]]; then
      set -x
    fi

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
    function cleanup {
      rm -rf "$TEMPDIR"
    }
    trap cleanup EXIT
    TEMPDIR=$(mktemp -d)
    pushd "$TEMPDIR" > /dev/null

    vars=$(
      nix-instantiate --eval --strict \
        --argstr system ${lib.escapeShellArg system} \
        --argstr username "$USER" \
        --argstr homeDirectory "$HOME" \
        --argstr args ${lib.escapeShellArg (__toJSON args)} \
        --argstr bare "''${bare:-}" \
        --expr '{ ... } @ args: {
          hmArgs = { inherit (args) system username homeDirectory; };
          args = __fromJSON args.args;
          bare = args.bare != "";
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
        inherit ($vars) hmArgs args bare;
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
                  (!bare && self.outputs.homeManagerProfiles.\''${username} or null != null)
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

    popd > /dev/null

    if [[ -n "''${dry:-}" ]]; then
      echo >&2 'Flake generated in:'
      echo "$TEMPDIR"
      echo >&2 'This directory will NOT be cleaned up.'

      trap EXIT
      exit 0
    fi

    cleanup
    trap EXIT

    function launch {
      declare -a prootArgs
      while read -r; do
        prootArgs+=(-b "$REPLY":"$HOME"/"''${REPLY#"$activationPackage"/home-files/}")
      done < <(find "$activationPackage"/home-files/ -not -type d)

      PATH="''${PATH:-}''${PATH:+:}"
      PATH="$PATH:$activationPackage/home-path/bin"
      PATH="$PATH:$activationPackage/home-path/sbin"

      exec proot \
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
}
