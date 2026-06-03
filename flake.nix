{
  description = "Konyak macOS Wine runtime build recipes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-darwin" "aarch64-darwin" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };
        crossoverSource = builtins.fromJSON (
          builtins.readFile ./sources/crossover.json
        );
      in
      {
        packages.konyak-macos-wine-runtime = pkgs.callPackage ./nix/wine-crossover.nix {
          inherit crossoverSource;
        };

        packages.default = self.packages.${system}.konyak-macos-wine-runtime;

        checks.fetch-crossover-source = pkgs.runCommand "fetch-crossover-source" { } ''
          cp ${pkgs.fetchurl {
            url = crossoverSource.url;
            hash = crossoverSource.hash;
          }} $out
        '';

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.bison
            pkgs.flex
            pkgs.jq
            pkgs.pkg-config
            pkgs.zstd
          ];
        };
      });
}
