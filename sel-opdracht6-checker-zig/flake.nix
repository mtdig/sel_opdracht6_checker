{
  description = "SELab Opdracht 6 Checker — Zig/SDL2 GUI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            zig

            # SDL2
            SDL2.dev
            SDL2_ttf

            # GL / X11 (needed at link time)
            libGL
            libx11
            libxcursor
            libxext
            libxfixes
            libxi
            libxinerama
            libxrandr
            libxrender

            # libcurl for HTTP/HTTPS (with TLS cert skip)
            curl.dev

            # Font for the GUI
            liberation_ttf

            pkg-config
          ];

          shellHook = ''
            export SEL_FONT_PATH="${pkgs.liberation_ttf}/share/fonts/truetype/LiberationMono-Regular.ttf"
            echo "sel-checker dev shell — zig $(zig version), SDL2 ready"
          '';
        };
      });
}
