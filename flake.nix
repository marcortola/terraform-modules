{
  description = "Terraform modules development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate = package: nixpkgs.lib.getName package == "terraform";
      };
      tools = with pkgs; [
        git
        nil
        nixfmt
        statix
        terraform
        terraform-ls
        tflint
      ];
      requiredTools = [
        "git"
        "nil"
        "nixfmt"
        "statix"
        "terraform"
        "terraform-ls"
        "tflint"
      ];
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = tools;
      };

      checks.${system}.dev-shell-tools =
        pkgs.runCommand "dev-shell-tools"
          {
            nativeBuildInputs = tools;
          }
          ''
            for tool in ${pkgs.lib.escapeShellArgs requiredTools}; do
              command -v "$tool" >/dev/null
            done
            touch "$out"
          '';
    };
}
