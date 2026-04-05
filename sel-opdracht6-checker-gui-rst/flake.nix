{
  description = "SELab Opdracht 6 Checker – Rust/egui GUI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; };

        # Stable Rust toolchain
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" ];
        };

        # Runtime libraries that egui/winit/glutin need to dlopen
        runtimeLibs = with pkgs; [
          # Wayland
          wayland
          libxkbcommon

          # X11
          libx11
          libxcursor
          libxrandr
          libxi
          libxcb

          # OpenGL / EGL
          libGL
          libGLU
          vulkan-loader
        ];

        # Build-time native dependencies
        buildInputs = with pkgs; [
          # Wayland
          wayland
          wayland-protocols
          wayland-scanner
          libxkbcommon

          # X11 / XCB
          libx11
          libxcursor
          libxrandr
          libxi
          libxcb
          libxrender

          # GL
          libGL
          libGLU

          # pkg-config deps
          fontconfig
          freetype
        ];

        nativeBuildInputs = with pkgs; [
          pkg-config
          cmake       # needed by some -sys crates (ring, etc.)
          rustToolchain
          cargo
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          inherit buildInputs nativeBuildInputs;

          # LD_LIBRARY_PATH so winit/glutin can dlopen wayland/x11/GL at runtime
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath runtimeLibs;

          shellHook = ''
            echo "🦀 Rust $(rustc --version | cut -d' ' -f2) — sel-checker dev shell"
          '';
        };
      });
}
