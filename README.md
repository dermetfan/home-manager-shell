# home-manager-shell

Spawns a shell in a home-manager profile. Like nix-shell for home-manager.

Builds your profile, sets `$PATH` to its `/bin`, and bind-mounts its files using [proot](https://proot-me.github.io/).

## Examples

Have a look at the [example flake](example/flake.nix). It implements all supported use cases.

Use your home-manager profile on a friend's machine:

	USER=myUserName nix run sourcehut:~dermetfan/home-manager-shell github:your/flake # FIXME USER= has no effect

## Usage

If the target flake provides a module in the `homeManagerProfiles.$USER` output it will be imported unless `-b` is given.

### Standalone

You can run against any arbitrary flake.

	home-manager-shell [options] <flake-ref> [command] [args]

### Library

See the [example flake](example/flake.nix).

Once you added such an app to your flake you can run it like this:

	nix run github:your/flake#app [options] [command] [args]

## CLI Options

- `-e`: Module to enable in the configuration. Can be given multiple times.
- `-i`: Line to add to the configuration's `imports` list verbatim. Can be given multiple times.
- `-a`: Line to add to the build arguments verbatim, will be terminated by `;`. Can be given multiple times.
- `-p`: Override the nixpkgs flake.
- `-l`: Override the home-manager flake.
- `-b`: Do not import `homeManagerProfiles.$USER` even if it exists.
- `-n`: Only write the temporary flake and exit.
- `-v`: Verbose output.
