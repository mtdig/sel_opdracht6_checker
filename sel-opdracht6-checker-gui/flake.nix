{
  description = "SELab Opdracht 6 Checker – JavaFX GUI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Full JDK (not headless) so JavaFX native libs can link
        jdk = pkgs.jdk21;

        # Runtime libs JavaFX needs
        javafxLibs = with pkgs; [
          libx11
          libxtst
          libxxf86vm
          libxi
          libxrandr
          libxcursor
          libxrender
          libxext
          gtk3
          glib
          pango
          cairo
          gdk-pixbuf
          atk
          libGL
          libGLU
          freetype
          fontconfig
          alsa-lib
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          name = "sel-checker-gui";

          buildInputs = [ jdk pkgs.maven ] ++ javafxLibs;

          shellHook = ''
            export JAVA_HOME="${jdk}"
            export PATH="${jdk}/bin:$PATH"

            # Let JavaFX find native libraries
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath javafxLibs}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

            echo "──────────────────────────────────────────"
            echo " SELab Opdracht 6 Checker – JavaFX shell"
            echo " Java:  $(java -version 2>&1 | head -1)"
            echo " Maven: $(mvn --version 2>&1 | head -1)"
            echo " Run:   mvn javafx:run"
            echo "──────────────────────────────────────────"
          '';
        };
      }
    );
}
