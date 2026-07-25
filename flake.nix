{
  description = "cl-tty-kit: a small Common Lisp terminal toolkit";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # cl-tty-kit itself is dependency-free; cl-prolog and cl-weave are both
  # :cl-tty-kit/test-only dependencies (see cl-tty-kit.asd :depends-on and
  # cl-tty-kit/test :depends-on). Neither is distributed by Quicklisp, and
  # this project keeps no vendored copy of either: these two flake inputs
  # are the only source of both, put on CL_SOURCE_REGISTRY by every
  # app/check/devShell below.
  inputs.cl-prolog.url = "github:nerima-lisp/cl-prolog";
  inputs.cl-prolog.inputs.nixpkgs.follows = "nixpkgs";
  inputs.cl-prolog.inputs.cl-weave.follows = "cl-weave";
  inputs.cl-prolog.inputs.paredit-cli.follows = "paredit-cli";

  inputs.cl-weave.url = "github:nerima-lisp/cl-weave";
  inputs.cl-weave.inputs.nixpkgs.follows = "nixpkgs";
  inputs.cl-weave.inputs.paredit-cli.follows = "paredit-cli";

  # paredit-cli provides structural S-expression tooling for this repo's
  # Lisp sources: a dev-shell binary for agent-driven refactors and a
  # structural-parse lint gate reused in `checks`.
  inputs.paredit-cli.url = "github:nerima-lisp/paredit-cli";
  inputs.paredit-cli.inputs.nixpkgs.follows = "nixpkgs";

  # contrib/cl-parser-kit-csi-grammar.lisp's dependency: an opt-in second,
  # independent declarative specification of the ECMA-48 CSI byte-class
  # grammar (see contrib/cl-prolog-csi-grammar.lisp for the first, built on
  # cl-prolog's DCG support instead). Never part of the core build/CI.
  inputs.cl-parser-kit.url = "github:nerima-lisp/cl-parser-kit";
  inputs.cl-parser-kit.inputs.nixpkgs.follows = "nixpkgs";
  inputs.cl-parser-kit.inputs.cl-prolog.follows = "cl-prolog";
  inputs.cl-parser-kit.inputs.cl-weave.follows = "cl-weave";
  inputs.cl-parser-kit.inputs.paredit-cli.follows = "paredit-cli";

  outputs =
    { self, nixpkgs, cl-prolog, cl-weave, paredit-cli, cl-parser-kit }:
    let
      # x86_64-darwin is deliberately absent: nixpkgs 26.11 (which
      # nixos-unstable now tracks) dropped support for it outright, so every
      # output for that platform fails to evaluate, not merely to build.
      # Listing it would make `nix flake check --all-systems` a guaranteed
      # error and advertise a platform this flake cannot serve.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forEachSystem = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};

      # Single source of truth for the project version: parse `:version`
      # straight out of cl-tty-kit.asd so the flake can never drift from the
      # ASDF system definition.
      projectVersion =
        let
          asd = builtins.readFile ./cl-tty-kit.asd;
          # Match only lines that are literally `:version "X"`, so a comment
          # or docstring merely mentioning :version can never shadow the
          # real definition.
          matches = builtins.filter (m: m != null) (
            map (builtins.match ''[[:space:]]*:version[[:space:]]+"([^"]+)".*'') (
              nixpkgs.lib.splitString "\n" asd
            )
          );
        in
        assert matches != [ ];
        builtins.head (builtins.head matches);

      sourceFor = pkgs: pkgs.lib.cleanSource ./.;

      # cl-prolog, cl-weave, and cl-parser-kit as raw ASDF-loadable source
      # trees (not the `packages` outputs above, which are shaped for
      # `lispLibs` composition rather than for CL_SOURCE_REGISTRY directly).
      # This -- not any vendored copy -- is the only place any
      # app/check/devShell below gets any of the three from. cl-parser-kit
      # is only a contrib/ dependency, but sharing one registry string with
      # cl-prolog/cl-weave keeps every entry point able to load contrib/
      # interactively without a separate CL_SOURCE_REGISTRY variant to track.
      clSourceRegistryFor = "${cl-prolog}//:${cl-weave}//:${cl-parser-kit}//:";

      # Runs a repository script against the current working directory (so
      # local edits are picked up without rebuilding a Nix package), with
      # CL_SOURCE_REGISTRY pointed at this flake's own cl-prolog/cl-weave
      # inputs so cl-tty-kit.asd's :depends-on resolves without any vendored
      # copy on disk.
      # `meta.description` is what `nix flake show` renders and what
      # `nix flake check` warns about when absent; these four apps are this
      # project's documented entry points (README, docs/src/installation.md,
      # RELEASING.md), so they carry one.
      scriptApp =
        pkgs: name: script: description:
        {
          type = "app";
          program = "${pkgs.writeShellScript name ''
            export CL_SOURCE_REGISTRY="${clSourceRegistryFor}''${CL_SOURCE_REGISTRY:-}"
            exec ${pkgs.sbcl}/bin/sbcl --script scripts/${script} "$@"
          ''}";
          meta = { inherit description; };
        };

      # `nix build .#docs` -- a hermetic, offline MkDocs (Material) build so
      # publishing to GitHub Pages never depends on a bare `pip install`
      # inside CI. Material for MkDocs bundles all of its own assets, so no
      # network access is required inside the Nix sandbox. Restricting `src`
      # to just mkdocs.yml and docs/src keeps this derivation's cache key
      # from changing on unrelated source/test edits, and `--strict` promotes
      # a broken internal link or an unlisted nav page to a build failure
      # instead of a silent gap once this is live.
      mkDocs =
        pkgs:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "cl-tty-kit-docs";
          version = projectVersion;
          src = pkgs.lib.fileset.toSource {
            root = ./docs;
            fileset = pkgs.lib.fileset.unions [
              ./docs/mkdocs.yml
              ./docs/src
            ];
          };
          nativeBuildInputs = [ pkgs.python3Packages.mkdocs-material ];
          buildPhase = ''
            runHook preBuild
            mkdocs build --strict --config-file mkdocs.yml --site-dir "$out"
            runHook postBuild
          '';
          dontInstall = true;
          meta = {
            description = "Rendered MkDocs (Material) documentation for cl-tty-kit";
            homepage = "https://github.com/nerima-lisp/cl-tty-kit";
            license = pkgs.lib.licenses.mit;
          };
        };
    in
    {
      formatter = forEachSystem (system: (pkgsFor system).nixpkgs-fmt);

      packages = forEachSystem (
        system:
        let
          pkgs = pkgsFor system;
          src = sourceFor pkgs;
        in
        {
          # No lispLibs: :cl-tty-kit itself is dependency-free (see
          # cl-tty-kit.asd) -- cl-prolog is only a :cl-tty-kit/test dependency.
          cl-tty-kit = pkgs.sbcl.buildASDFSystem {
            pname = "cl-tty-kit";
            version = projectVersion;
            inherit src;
            systems = [ "cl-tty-kit" ];
          };
          default = self.packages.${system}.cl-tty-kit;

          # `nix build .#coverage-report` -- a hermetic equivalent of
          # `sbcl --script scripts/coverage.lisp`, for CI to upload as an
          # artifact without a local SBCL/submodule checkout.
          coverage-report = pkgs.runCommand "cl-tty-kit-coverage-report" { nativeBuildInputs = [ pkgs.sbcl ]; } ''
            cp -R ${src} source
            chmod -R u+w source
            cd source
            export HOME="$TMPDIR/home"
            export XDG_CACHE_HOME="$TMPDIR/cache"
            mkdir -p "$HOME" "$XDG_CACHE_HOME"
            export CL_SOURCE_REGISTRY="${clSourceRegistryFor}$PWD//:"
            timeout 300 sbcl --script scripts/coverage.lisp
            mkdir -p "$out"
            cp -R coverage/. "$out/"
          '';

          docs = mkDocs pkgs;
        }
      );

      checks = forEachSystem (
        system:
        let
          pkgs = pkgsFor system;
          src = sourceFor pkgs;
        in
        {
          # Structural parse gate over every tracked Lisp source: fails if
          # any .lisp/.asd file is not a balanced S-expression document.
          paredit-lint = paredit-cli.lib.${system}.mkLintCheck {
            inherit src;
            name = "cl-tty-kit-paredit-lint";
          };

          # Hermetic equivalent of `sbcl --script scripts/test.lisp`.
          test = pkgs.runCommand "cl-tty-kit-test" { nativeBuildInputs = [ pkgs.sbcl ]; } ''
            cp -R ${src} source
            chmod -R u+w source
            cd source
            export HOME="$TMPDIR/home"
            export XDG_CACHE_HOME="$TMPDIR/cache"
            mkdir -p "$HOME" "$XDG_CACHE_HOME"
            export CL_SOURCE_REGISTRY="${clSourceRegistryFor}$PWD//:"
            timeout 600 sbcl --non-interactive \
              --eval '(require :asdf)' \
              --eval '(asdf:load-asd (truename "cl-tty-kit.asd"))' \
              --eval '(asdf:test-system :cl-tty-kit)'
            touch $out
          '';

          formatting = pkgs.runCommand "cl-tty-kit-nix-formatting" { nativeBuildInputs = [ pkgs.nixpkgs-fmt ]; } ''
            nixpkgs-fmt --check ${./flake.nix}
            touch $out
          '';
        }
      );

      devShells = forEachSystem (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            # sbcl brings sb-posix and sb-unicode as built-in contribs, so no
            # separate Quicklisp bootstrap is required for the core system.
            # paredit-cli is the structural refactoring tool for this repo's
            # Lisp sources. git is kept for ordinary repository work.
            packages = [
              pkgs.sbcl
              pkgs.git
              pkgs.nixpkgs-fmt
              paredit-cli.packages.${system}.default
            ];
            # The only place cl-prolog/cl-weave come from: cl-tty-kit.asd's
            # :depends-on cannot resolve either without this.
            shellHook = ''
              export CL_SOURCE_REGISTRY="$PWD//:${clSourceRegistryFor}''${CL_SOURCE_REGISTRY:-}"
            '';
          };
        }
      );

      apps = forEachSystem (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          # Mirrors .github/workflows/ci.yml's nix job, so
          # `nix run .#test` (etc.) matches what CI actually runs.
          test = scriptApp pkgs "cl-tty-kit-test" "test.lisp" "Run the cl-tty-kit test suite";
          verify = scriptApp pkgs "cl-tty-kit-verify" "verify.lisp" "Run the full release gate: tests, examples, and the source-registry smoke";
          coverage = scriptApp pkgs "cl-tty-kit-coverage" "coverage.lisp" "Regenerate the sb-cover report under coverage/";
          default = scriptApp pkgs "cl-tty-kit-test" "test.lisp" "Run the cl-tty-kit test suite";
        }
      );
    };
}
