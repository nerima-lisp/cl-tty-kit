{
  description = "cl-tty-kit: a small Common Lisp terminal toolkit";

  # nixos-unstable, not nixpkgs-unstable: it only advances after the NixOS
  # release tests pass, so it is less likely to land a broken build.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # Every sibling is pinned to a release tag. A bare
  # `github:nerima-lisp/cl-weave` follows that repository's default branch,
  # so an upstream push to main would break this repository's CI with no
  # change here and no warning. `inputs.nixpkgs.follows` is mandatory for the
  # same reason everywhere: without it each input drags in its own nixpkgs,
  # inflating flake.lock and rebuilding identical derivations.

  # cl-tty-kit.asd names one real (non-test) sibling dependency,
  # cl-codec-kit (declared further below, near cl-parser-kit); cl-prolog and
  # cl-weave are both :cl-tty-kit/test-only dependencies (see cl-tty-kit.asd
  # :depends-on and cl-tty-kit/test :depends-on). None of the three is
  # distributed by Quicklisp, and this project keeps no vendored copy of any:
  # these flake inputs are the only source of all three, put on
  # CL_SOURCE_REGISTRY by every app/check/devShell below.
  inputs.cl-prolog.url = "github:nerima-lisp/cl-prolog/v1.3.0";
  inputs.cl-prolog.inputs.nixpkgs.follows = "nixpkgs";
  inputs.cl-prolog.inputs.cl-weave.follows = "cl-weave";
  inputs.cl-prolog.inputs.paredit-cli.follows = "paredit-cli";

  inputs.cl-weave.url = "github:nerima-lisp/cl-weave/v1.1.4";
  inputs.cl-weave.inputs.nixpkgs.follows = "nixpkgs";
  inputs.cl-weave.inputs.paredit-cli.follows = "paredit-cli";

  # cl-codec-kit: cl-tty-kit.asd's one REAL (non-test) sibling dependency --
  # src/utf8.lisp delegates its UTF-8 codec to it. Built directly from
  # source via buildASDFSystem below (see cl-codec-kit-lib), not through its
  # own flake outputs, so `flake = false` and no `inputs.nixpkgs.follows`:
  # only the source tree is needed, not cl-codec-kit's own transitive flake
  # graph (cl-nix-forge, its own cl-weave, treefmt-nix).
  inputs.cl-codec-kit.url = "github:nerima-lisp/cl-codec-kit/v0.4.0";
  inputs.cl-codec-kit.flake = false;

  # cl-concurrent-kit: cl-tty-kit.asd's other REAL (non-test) sibling
  # dependency -- src/raw-mode.lisp takes its mutex from it instead of
  # SB-THREAD directly. Built directly from source via buildASDFSystem below
  # (see cl-concurrent-kit-lib), not through its own flake outputs, so
  # `flake = false` and no `inputs.nixpkgs.follows`: cl-concurrent-kit.asd's
  # own :depends-on is (), so there is no transitive flake graph to
  # propagate `.follows` into.
  inputs.cl-concurrent-kit.url = "github:nerima-lisp/cl-concurrent-kit/v0.5.0";
  inputs.cl-concurrent-kit.flake = false;

  # paredit-cli provides structural S-expression tooling for this repo's
  # Lisp sources: a dev-shell binary for agent-driven refactors and a
  # structural-parse lint gate reused in `checks`.
  inputs.paredit-cli.url = "github:nerima-lisp/paredit-cli/v1.4.0";
  inputs.paredit-cli.inputs.nixpkgs.follows = "nixpkgs";

  # contrib/cl-parser-kit-csi-grammar.lisp's dependency: an opt-in second,
  # independent declarative specification of the ECMA-48 CSI byte-class
  # grammar (see contrib/cl-prolog-csi-grammar.lisp for the first, built on
  # cl-prolog's DCG support instead). Never part of the core build/CI.
  inputs.cl-parser-kit.url = "github:nerima-lisp/cl-parser-kit/v1.0.3";
  inputs.cl-parser-kit.inputs.nixpkgs.follows = "nixpkgs";
  inputs.cl-parser-kit.inputs.cl-prolog.follows = "cl-prolog";
  inputs.cl-parser-kit.inputs.cl-weave.follows = "cl-weave";
  inputs.cl-parser-kit.inputs.paredit-cli.follows = "paredit-cli";

  # Drives `nix fmt` and the checks.formatting gate.
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
  inputs.treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

  # `crane` for Common Lisp/ASDF; used here for FROMASDSYSTEM's tested
  # `:version` extraction, replacing this flake's own hand-rolled regex.
  inputs.cl-nix-forge.url = "github:nerima-lisp/cl-nix-forge/v0.4.0";
  inputs.cl-nix-forge.inputs.nixpkgs.follows = "nixpkgs";
  inputs.cl-nix-forge.inputs.treefmt-nix.follows = "treefmt-nix";

  outputs =
    {
      self,
      nixpkgs,
      cl-prolog,
      cl-weave,
      cl-codec-kit,
      cl-concurrent-kit,
      paredit-cli,
      cl-parser-kit,
      treefmt-nix,
      cl-nix-forge,
    }:
    let
      # x86_64-linux is what CI gates; aarch64-darwin is the development
      # machine. Every per-system output -- packages, checks, apps AND devShells
      # -- comes from this one list, so leaving aarch64-darwin out takes `nix
      # build` and `nix develop` off the development machine as well. That trade
      # was made on 2026-08-01 and reverted on 2026-08-02; aarch64-darwin carries
      # no CI gate, which PACKAGE_STANDARD.md's "systems" section accepts
      # explicitly. aarch64-linux and x86_64-darwin are nobody's verification and
      # are not declared.
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};

      # treefmt drives `nix fmt` and the checks.formatting gate. Scope is Nix
      # only: nixfmt is a low-diff, no-footgun formatter, whereas a YAML
      # formatter mangles the GitHub Actions `on:` key and reformatting
      # Markdown would churn all 24 docs pages for no gain.
      treefmtEval = forAllSystems (
        system:
        treefmt-nix.lib.evalModule (pkgsFor system) {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        }
      );

      # Single source of truth for the project version: FROMASDSYSTEM reads
      # `:version` straight out of cl-tty-kit.asd (failing loudly on an
      # unrecognized shape) so the flake can never drift from the ASDF system
      # definition. Version extraction has no per-system output, so this picks
      # one arbitrary system's `lib` -- x86_64-linux, always in `systems`.
      projectVersion = cl-nix-forge.lib.x86_64-linux.fromAsdSystem ./cl-tty-kit.asd;

      sourceFor = pkgs: pkgs.lib.cleanSource ./.;

      # cl-codec-kit, cl-concurrent-kit, cl-prolog, cl-weave, and
      # cl-parser-kit as raw ASDF-loadable source trees (not the `packages`
      # outputs above, which are shaped for `lispLibs` composition rather
      # than for CL_SOURCE_REGISTRY directly). This -- not any vendored copy
      # -- is the only place any app/check/devShell below gets any of the
      # five from. cl-codec-kit and cl-concurrent-kit are the two REAL
      # (non-test) dependencies here, needed at every script entry point
      # exactly as much as at build time (raw-mode.lisp is loaded as part of
      # ordinary system loading, not an optional contrib layer); cl-prolog
      # and cl-weave are test-only; cl-parser-kit is only a contrib/
      # dependency, but sharing one registry string keeps every entry point
      # able to load contrib/ interactively without a separate
      # CL_SOURCE_REGISTRY variant to track.
      clSourceRegistryFor = "${cl-codec-kit}//:${cl-concurrent-kit}//:${cl-prolog}//:${cl-weave}//:${cl-parser-kit}//:";

      # cl-codec-kit as a buildASDFSystem lib for cl-tty-kit's own :depends-on
      # (see cl-tty-kit.asd). Built directly from the flake = false source
      # input above rather than through cl-codec-kit's own flake outputs.
      cl-codec-kit-lib =
        pkgs:
        pkgs.sbcl.buildASDFSystem {
          pname = "cl-codec-kit";
          version = "0.3.1";
          src = cl-codec-kit;
          systems = [ "cl-codec-kit" ];
        };

      # cl-concurrent-kit as a buildASDFSystem lib for cl-tty-kit's own
      # :depends-on (see cl-tty-kit.asd). Built directly from the
      # flake = false source input above rather than through
      # cl-concurrent-kit's own flake outputs.
      cl-concurrent-kit-lib =
        pkgs:
        pkgs.sbcl.buildASDFSystem {
          pname = "cl-concurrent-kit";
          version = "0.5.0";
          src = cl-concurrent-kit;
          systems = [ "cl-concurrent-kit" ];
        };

      # Runs a repository script against the current working directory (so
      # local edits are picked up without rebuilding a Nix package), with
      # CL_SOURCE_REGISTRY pointed at this flake's own cl-prolog/cl-weave
      # inputs so cl-tty-kit.asd's :depends-on resolves without any vendored
      # copy on disk.
      # `meta.description` is what `nix flake show` renders and what
      # `nix flake check` warns about when absent; these four apps are this
      # project's documented entry points (README, docs/src/getting-started.md,
      # RELEASING.md), so they carry one.
      # `script` is a path relative to the repository root, so the test entry
      # point can live at the root (run-tests.lisp, per the org standard)
      # while the other three stay under scripts/.
      scriptApp = pkgs: name: script: description: {
        type = "app";
        program = "${pkgs.writeShellScript name ''
          runtime_dir="$(${pkgs.coreutils}/bin/mktemp -d)"
          export HOME="$runtime_dir/home"
          export XDG_CACHE_HOME="$runtime_dir/cache"
          export XDG_CONFIG_HOME="$runtime_dir/config"
          mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"
          export CL_SOURCE_REGISTRY="$PWD//:${clSourceRegistryFor}"
          export PATH="${pkgs.sbcl}/bin:$PATH"

          status=0
          ${pkgs.coreutils}/bin/timeout --kill-after=30s 600 ${pkgs.sbcl}/bin/sbcl --script ${script} "$@" || status=$?
          rm -rf "$runtime_dir"
          exit "$status"
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
            ${pkgs.coreutils}/bin/timeout --kill-after=30s 300 \
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
      # `nix fmt` entry point.
      formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);

      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          src = sourceFor pkgs;
        in
        {
          # lispLibs carries cl-codec-kit and cl-concurrent-kit,
          # :cl-tty-kit's two real (non-test) :depends-on entries (see
          # cl-tty-kit.asd) -- cl-prolog and cl-weave remain
          # :cl-tty-kit/test-only dependencies, resolved instead through
          # CL_SOURCE_REGISTRY (clSourceRegistryFor) everywhere else.
          cl-tty-kit = pkgs.sbcl.buildASDFSystem {
            pname = "cl-tty-kit";
            version = projectVersion;
            inherit src;
            systems = [ "cl-tty-kit" ];
            lispLibs = [
              (cl-codec-kit-lib pkgs)
              (cl-concurrent-kit-lib pkgs)
            ];
          };
          default = self.packages.${system}.cl-tty-kit;

          # `nix build .#coverage-report` -- a hermetic equivalent of
          # `sbcl --script scripts/coverage.lisp`, for CI to upload as an
          # artifact without a local SBCL/submodule checkout.
          coverage-report =
            pkgs.runCommand "cl-tty-kit-coverage-report"
              {
                nativeBuildInputs = [
                  pkgs.perl
                  pkgs.sbcl
                ];
              }
              ''
                  # SB-COVER derives its HTML names from source pathnames.  A
                  # build-directory-relative source copy makes those names vary
                  # per invocation, so use Nix's fixed output path instead.
                  work="$out/work"
                  mkdir -p "$work"
                  cp -R ${src}/. "$work/"
                  chmod -R u+w "$work"
                  cd "$work"
                export HOME="$TMPDIR/home"
                export XDG_CACHE_HOME="$TMPDIR/cache"
                mkdir -p "$HOME" "$XDG_CACHE_HOME"
                export CL_SOURCE_REGISTRY="${clSourceRegistryFor}$PWD//:"
                  ${pkgs.coreutils}/bin/timeout --kill-after=30s 420 sbcl --script scripts/coverage.lisp
                  cp -R coverage/. "$out/"
                  perl scripts/normalize-coverage-report.pl "$out" "$work"
                  rm -rf "$work"
              '';

          docs = mkDocs pkgs;
        }
      );

      # Granularity lives here, NOT in extra GitHub Actions jobs: `nix flake
      # check` evaluates each attribute as its own derivation, in parallel,
      # with build caching. Add a check here rather than a job in ci.yml.
      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          src = sourceFor pkgs;
        in
        {
          # Hermetic equivalent of `sbcl --script run-tests.lisp`. The tree is
          # copied and made writable because ASDF compiles into it; HOME and
          # XDG_CACHE_HOME move the fasl cache somewhere writable too.
          default = pkgs.runCommand "cl-tty-kit-test" { nativeBuildInputs = [ pkgs.sbcl ]; } ''
            cp -R ${src} source
            chmod -R u+w source
            cd source
            export HOME="$TMPDIR/home"
            export XDG_CACHE_HOME="$TMPDIR/cache"
            mkdir -p "$HOME" "$XDG_CACHE_HOME"
            export CL_SOURCE_REGISTRY="${clSourceRegistryFor}$PWD//:"
            ${pkgs.coreutils}/bin/timeout --kill-after=30s 600 sbcl --script run-tests.lisp
            touch $out
          '';

          # Structural parse gate over every tracked Lisp source: fails if
          # any .lisp/.asd file is not a balanced S-expression document.
          paredit-lint = paredit-cli.lib.${system}.mkLintCheck {
            inherit src;
            name = "cl-tty-kit-paredit-lint";
          };

          # Fails `nix flake check` when any tracked Nix file is unformatted,
          # which is what turns `nix fmt` from a suggestion into a gate.
          formatting = treefmtEval.${system}.config.build.check self;

          # packages.docs runs `mkdocs build --strict`, so a broken link or a
          # page missing from the nav fails here. Without it in `checks` the
          # docs are only built by docs.yml, which runs *after* the merge to
          # main - so such a break surfaces as a failed deploy rather than as
          # a failed pull request.
          docs = self.packages.${system}.docs;
        }
      );

      devShells = forAllSystems (
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
              treefmtEval.${system}.config.build.wrapper
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

      apps = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          # Mirrors .github/workflows/ci.yml's check job, so
          # `nix run .#test` (etc.) matches what CI actually runs.
          test = scriptApp pkgs "cl-tty-kit-test" "run-tests.lisp" "Run the cl-tty-kit test suite";
          verify =
            scriptApp pkgs "cl-tty-kit-verify" "scripts/verify.lisp"
              "Run the full release gate: tests, examples, and the source-registry smoke";
          coverage =
            scriptApp pkgs "cl-tty-kit-coverage" "scripts/coverage.lisp"
              "Regenerate the sb-cover report under coverage/";
          benchmark-renderer =
            scriptApp pkgs "cl-tty-kit-benchmark-renderer" "scripts/benchmark-renderer.lisp"
              "Measure the sparse render-diff hot path";
          examples =
            scriptApp pkgs "cl-tty-kit-examples" "scripts/examples.lisp"
              "Run every documented example as a smoke test";
          source-registry-smoke =
            scriptApp pkgs "cl-tty-kit-source-registry-smoke" "scripts/source-registry-smoke.lisp"
              "Verify clean-process ASDF source-registry discovery";
          default = scriptApp pkgs "cl-tty-kit-test" "run-tests.lisp" "Run the cl-tty-kit test suite";
        }
      );
    };
}
