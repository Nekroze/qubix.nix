{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./desktop.nix
    ./laptop.nix
    ./networking.nix
    ./security.nix
    ./qubix.nix
  ];

  qubix.enable = true;
  qubix.sshKeyFiles = [ /home/nekroze/.ssh/id_ed25519.pub ];
  qubix.workspaces = {
    tester = {
      autostart = true;
      proxy = "lab";
    };
  };
  qubix.proxies = {
    lab = {
      autostart = true;
    };
  };
}
