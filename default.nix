{
  self,
  system,
  nixpkgs,
  home-manager,
  enable ? [],
  disable ? [],
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
        declare -a enable disable imports args

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

        while getopts :e:E:i:a:p:l:U:H:dDcbnvh opt; do
          case "$opt" in
            e) enable+=("$OPTARG.enable = lib.mkOverride 30 true;"$'\n'); disableAll=1 ;;
            E) disable+=("$OPTARG.enable = lib.mkOverride 30 false;"$'\n') ;;
            i) imports+=("$OPTARG"$'\n') ;;
            a) args+=("$OPTARG;"$'\n') ;;
            p) nixpkgs="$OPTARG" ;;
            l) homeManager="$OPTARG" ;;
            U) user="$OPTARG" ;;
            H) home="$OPTARG" ;;
            d) disableAll=1 ;;
            D) unset disableAll ;;
            c) interactive=1 ;;
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
        disable+=(${lib.escapeShellArgs disable})
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
            --argstr disableAll "''${disableAll:-}" \
            --expr '{ ... } @ args: {
              inherit (args) system;
              module.home = { inherit (args) username homeDirectory; };
              args = __fromJSON args.args;
              bare = args.bare != "";
              disableAll = args.disableAll != "";
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
            inherit ($vars) args bare disableAll module system;

            stage1Args = (
              let
                targetPkgs =
                  target.outputs.legacyPackages.\''${system} or
                  nixpkgs.outputs.legacyPackages.\''${system};
              in
              nixpkgs.lib.recursiveUpdate rec {
                pkgs = targetPkgs;

                extraSpecialArgs.self = target;

                modules = [
                  module

                  ({ self, options, config, lib, pkgs, ... }: {
                    imports =
                      [ ''${imports[*]} ] ++
                      lib.optional
                        (!bare && self.outputs.homeManagerProfiles.\''${module.home.username} or null != null)
                        self.outputs.homeManagerProfiles.\''${module.home.username};
                  })

                  ({ lib, ... }: {
                    nixpkgs.config = lib.mkForce (
                      targetPkgs.config //
                      { allowUnfree = true; }
                    );

                    home.stateVersion = with lib; versions.majorMinor version;

                    # Disable by default because the \`nix.conf\` check fails if \`nix.package\` is not set.
                    # We want to override \`lib.mkOptionDefault\` at priority 1500 but not \`lib.mkDefault\` at priority 1000.
                    nix.enable = lib.mkOverride 1400 false;
                  })
                ];

                ''${args[*]}
              } args
            );
            stage1Eval = home-manager.lib.homeManagerConfiguration stage1Args;
          in rec {
            homeManagerConfigurations.default = home-manager.lib.homeManagerConfiguration (stage1Args // {
              modules = stage1Args.modules ++ [
                ({ lib, ... }: {
                  config = {
                    ''${enable[*]}
                    ''${disable[*]}
                  };
                })

                ({ lib, ... }: {
                  config = lib.mkIf disableAll (
                    let
                      mapOptionsDisable = ns: {
                        \''${ns} = lib.filterAttrs (_: v: v != null) (
                          builtins.mapAttrs
                          (_: o: if o ? enable && o.visible or false then {
                            # we want to override \`mkForce\` which has prio 50
                            enable = lib.mkOverride 40 false;
                          } else null)
                          stage1Eval.options.\''${ns}
                        );
                      };
                    in
                      mapOptionsDisable "programs" //
                      mapOptionsDisable "services"
                  );
                })
              ];
            });

            defaultPackage.\''${system} = packages.\''${system}.default;
            packages.\''${system}.default = homeManagerConfigurations.default.activationPackage;
          };
        }
        EOF

        if [[ -n "''${interactive:-}" ]]; then
          "$EDITOR" flake.nix
        fi

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

          PATH="$activationPackage/home-path/bin''${PATH:+:}''${PATH:-}"
          PATH="$activationPackage/home-path/sbin''${PATH:+:}''${PATH:-}"

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
