{
  description = "SELab Opdracht6 Checker — shell with all checker.sh dependencies";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    in
    {
      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in
        {
          default = pkgs.mkShell {
            name = "sel-checker";
            packages = with pkgs; [
              bash
              curl
              jq
              mariadb.client
              openssh
              sshpass
              iputils   # ping
              netcat-openbsd
              openssl
            ];

            shellHook = ''
              echo "SELab checker shell ready."
              echo "Usage: DECRYPT_PASS=\"...\" TARGET=192.168.56.20 bash checker.sh"
            '';
          };
        });

      apps = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in
        {
          default = {
            type = "app";
            program = toString (pkgs.writeShellScript "run-checker" ''
              export PATH="${pkgs.lib.makeBinPath (with pkgs; [
                bash curl jq mariadb.client openssh sshpass iputils netcat-openbsd openssl
              ])}:$PATH"
              exec bash "$(dirname "$0")/../checker.sh" "$@"
            '');
          };
        });
    };
}
