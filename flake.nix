{
  description = "Konyak macOS Wine runtime build recipes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-llvm15.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixpkgs-llvm15, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-darwin" "aarch64-darwin" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };
        llvm15Pkgs = import nixpkgs-llvm15 { inherit system; };
        crossoverSource = builtins.fromJSON (
          builtins.readFile ./sources/crossover.json
        );
        dxmtSource = builtins.fromJSON (
          builtins.readFile ./sources/dxmt.json
        );
        metalToolchainBinEnv = builtins.getEnv "KONYAK_METAL_TOOLCHAIN_BIN";
        metalToolchainBin =
          if metalToolchainBinEnv == "" then null else metalToolchainBinEnv;
        llvm15 = pkgs.symlinkJoin {
          name = "konyak-dxmt-llvm-15";
          paths = [
            llvm15Pkgs.llvmPackages_15.llvm
            llvm15Pkgs.llvmPackages_15.llvm.dev
            llvm15Pkgs.llvmPackages_15.llvm.lib
          ];
        };
      in
      {
        packages.konyak-macos-wine-runtime = pkgs.callPackage ./nix/wine-crossover.nix {
          inherit crossoverSource;
        };

        packages.konyak-macos-dxmt = pkgs.callPackage ./nix/dxmt.nix {
          inherit dxmtSource llvm15 metalToolchainBin;
          wineRuntime = self.packages.${system}.konyak-macos-wine-runtime;
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
            pkgs.git
            pkgs.jq
            pkgs.meson
            pkgs.ninja
            pkgs.pkg-config
            pkgs.zstd
          ];
        };
      });
}
