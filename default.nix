{
  self,
  system,
  nixpkgs,
  home-manager,
  enable ? [],
  imports ? [],
  args ? {},
}: let
  pkgs = nixpkgs.legacyPackages.${system};
  inherit (nixpkgs) lib;
in
  pkgs.writeShellApplication {
    name = "home-manager-shell";
    runtimeInputs = with pkgs; [proot jq findutils];
    text =
      ''
        declare -a enable imports args

        function usage {
          {
            echo 'Usage:'
            echo
            #shellcheck disable=SC2016
            echo ${
          # https://github.com/kamadorueda/alejandra/issues/242
          lib.pipe ./cli.txt [
            lib.fileContents
            (lib.splitString "\n")
            (map (line: "\t" + line))
            (lib.concatStringsSep "\n")
            lib.escapeShellArg
          ]
        }
          } >&2
        }

        while getopts :e:i:c:a:p:l:U:H:bnvh opt; do
          case "$opt" in
            e) enable+=("$OPTARG.enable = true;"$'\n') ;;
            i) imports+=("$OPTARG"$'\n') ;;
            a) args+=("$OPTARG;"$'\n') ;;
            p) nixpkgs="$OPTARG" ;;
            l) homeManager="$OPTARG" ;;
            U) user="$OPTARG" ;;
            H) home="$OPTARG" ;;
            b) bare=1 ;;
            n) dry=1 ;;
            v) verbose=1 ;;
            h)
              usage
              exit
              ;;
            *)
              >&2 echo 'Unknown flag'
              >&2 echo
              usage
              exit 1
              ;;
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

        user="''${user:-"$USER"}"
        home="''${home:-"$HOME"}"
      ''
      + (
        if self != null
        then ''
          target=${lib.escapeShellArg self}
        ''
        else ''
          target="$1"
          shift
        ''
      )
      + ''
        function cleanup {
          rm -rf "$TEMPDIR"
        }
        trap cleanup EXIT
        TEMPDIR=$(mktemp -d)
        pushd "$TEMPDIR" > /dev/null

        vars=$(
          nix-instantiate --eval --strict \
            --argstr system ${lib.escapeShellArg system} \
            --argstr username "$user" \
            --argstr homeDirectory "$home" \
            --argstr args ${lib.escapeShellArg (__toJSON args)} \
            --argstr bare "''${bare:-}" \
            --expr '{ ... } @ args: {
              args =
                { inherit (args) system username homeDirectory; } //
                __fromJSON args.args;
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

          outputs = { target, nixpkgs, home-manager, ... }: let
            inherit ($vars) args bare;
            inherit (args) system username;
          in rec {
            homeManagerConfigurations.default = home-manager.lib.homeManagerConfiguration (
              nixpkgs.lib.recursiveUpdate rec {
                pkgs =
                  target.outputs.legacyPackages.\''${system} or
                  nixpkgs.outputs.legacyPackages.\''${system};

                extraSpecialArgs.self = target;

                configuration = { self, config, lib, pkgs, ... }: rec {
                  imports = [ ''${imports[*]} ] ++
                    lib.optional
                      (!bare && self.outputs.homeManagerProfiles.\''${username} or null != null)
                      self.outputs.homeManagerProfiles.\''${username};

                  ''${enable[*]}
                };

                ''${args[*]}
              } args
            );

            defaultPackage.\''${system} = packages.\''${system}.default;
            packages.\''${system}.default = homeManagerConfigurations.default.activationPackage;
          };
        }
        EOF

        nix flake lock

        activationPackage=$(
          nix build --json --impure | jq -r '.[].outputs.out'
        )
        profileDirectory=$(
          nix eval --raw --impure .#homeManagerConfigurations.default.config.home.profileDirectory
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
            prootArgs+=(-b "$REPLY":"$home/''${REPLY#"$activationPackage/home-files/"}")
          done < <(find "$activationPackage/home-files/" -not -type d)

          prootArgs+=(-b "$activationPackage/home-path":"$profileDirectory")

          __HM_SESS_VARS_SOURCED=
          #shellcheck disable=SC1091
          source "$activationPackage/home-path/etc/profile.d/hm-session-vars.sh"

          USER="$user"
          HOME="$home"

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
