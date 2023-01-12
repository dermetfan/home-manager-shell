# home-manager-shell

Spawns a shell in a home-manager profile. Like nix-shell for home-manager.

Builds your profile, sets its env vars and `$PATH` to its `/bin`, and bind-mounts its files using [proot](https://proot-me.github.io/).

## Usage

If the target flake provides a module in the `homeManagerProfiles.$USER` output it will be imported (unless `-b` is given).

Otherwise use `-i` to add custom imports. `self`, `config`, `lib`, and `pkgs` are available in its scope.
Quickly enable programs using `-e` which is a shortcut for `-i '{ programs.$PROGRAM.enable = true; }'`.

Using `-U` and `-H` you can set username and home directory to adapt the build to your current machine.
If not given, these default to the values of your current `USER` and `HOME` environment variables.

### Standalone

You can run against any arbitrary flake:

	home-manager-shell [OPTION]… FLAKE_REF [COMMAND]…

### Library

You can add an app to your flake for a shorter command line and static configuration.
See the [example flake](example/flake.nix) on how to do this.

Once you added such an app to your flake you can run it like this:

	nix run github:your/flake#app -- [OPTION]… [COMMAND]…

### CLI Options

See [cli.txt](cli.txt).

### Examples

Use your home-manager profile on a friend's machine without installing it:

	nix run sourcehut:~dermetfan/home-manager-shell -- -U my_user github:your/flake

Try a friend's home-manager profile without installing it:

	nix run sourcehut:~dermetfan/home-manager-shell github:friends/flake

Run in a temporary home directory ([library](#library) usage assumed for shorter example):

	nix run github:your/flake#app -- -H /tmp/test-home
