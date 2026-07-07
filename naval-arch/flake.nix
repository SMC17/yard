{
  description = "Yard Naval Architecture - Zig Models";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              zig
              zls
            ];
          };
        }
      );

      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.stdenv.mkDerivation {
            name = "yard-naval-arch-zig";
            src = ./.;

            nativeBuildInputs = [ pkgs.zig ];

            buildPhase = ''
              export HOME=$TMPDIR
              zig build -Doptimize=ReleaseSafe --prefix $out
            '';
          };
        }
      );
    };
}
