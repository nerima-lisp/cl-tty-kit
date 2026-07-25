{
  description = "cl-tty-kit: a small Common Lisp terminal toolkit";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forEachSystem = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
      # Runs a repository script from the current working directory rather
      # than from the flake's own (submodule-free) source copy: ASDF loading
      # this system needs vendor/cl-prolog and vendor/cl-weave, which are git
      # submodules `git submodule update --init` populates locally but that
      # Nix's git-tracked-files filtering of `self` never includes. Running
      # against the working directory is exactly what the README and CI
      # already do (`sbcl --script scripts/<name>.lisp` from a checkout with
      # submodules initialized), so this stays consistent with them instead
      # of re-deriving a hermetic build that this project's architecture
      # doesn't support.
      scriptApp =
        pkgs: name: script:
        {
          type = "app";
          program = "${pkgs.writeShellScript name ''
            exec ${pkgs.sbcl}/bin/sbcl --script scripts/${script} "$@"
          ''}";
        };
    in
    {
      devShells = forEachSystem (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            # git is needed for `git submodule update --init` (vendor/cl-prolog,
            # vendor/cl-weave -- see README "Installation"); sbcl brings sb-posix
            # and sb-unicode as built-in contribs, so no separate Quicklisp
            # bootstrap is required for the core system.
            packages = [
              pkgs.sbcl
              pkgs.git
            ];
          };
        }
      );

      apps = forEachSystem (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          # Mirrors .github/workflows/ci.yml's verify/coverage/test steps, so
          # `nix run .#test` (etc.), run from a checkout with submodules
          # initialized, matches what CI actually runs.
          test = scriptApp pkgs "cl-tty-kit-test" "test.lisp";
          verify = scriptApp pkgs "cl-tty-kit-verify" "verify.lisp";
          coverage = scriptApp pkgs "cl-tty-kit-coverage" "coverage.lisp";
          default = scriptApp pkgs "cl-tty-kit-test" "test.lisp";
        }
      );
    };
}
