{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    crane.url = "github:ipetkov/crane";
    crane.inputs.nixpkgs.follows = "nixpkgs";
    advisory-db.url = "github:rustsec/advisory-db";
    advisory-db.flake = false;
  };

  outputs = inputs @ {
    nixpkgs,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];

      perSystem = {
        config,
        pkgs,
        system,
        inputs',
        self',
        ...
      }: let
        pkgs = nixpkgs.legacyPackages.${system};
        advisory-db = inputs.advisory-db;
        craneLib = inputs.crane.mkLib pkgs;

        runtimeInputs = with pkgs; [glib vips];
        nativeBuildInputs = with pkgs; [openssl pkg-config];
        src = craneLib.cleanCargoSource ./.;

        ore-cli = craneLib.buildPackage {
          inherit src nativeBuildInputs;
          doCheck = false;
          buildInputs = runtimeInputs;
        };

        cargoArtifacts = craneLib.buildDepsOnly {inherit src nativeBuildInputs;};

      in {
        checks = {
          inherit ore-cli;

          # Clippy
          ore-cli-clippy = craneLib.cargoClippy {
            inherit cargoArtifacts src;
            cargoClippyExtraArgs = "--all-targets -- --deny warnings";
          };

          # Check formatting
          ore-cli-fmt = craneLib.cargoFmt {inherit src;};

          # Audit dependencies
          ore-cli-audit = craneLib.cargoAudit {inherit src advisory-db;};

          # Run tests with cargo-nextest
          ore-cli-nextest = craneLib.cargoNextest {
            inherit cargoArtifacts src;
            buildInputs = runtimeInputs; # needed for tests
            partitions = 1;
            partitionType = "count";
          };
        };

        packages = {
          default = ore-cli;
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = builtins.attrValues self'.checks;
          packages = runtimeInputs ++ nativeBuildInputs;
        };
      };
    };
}
