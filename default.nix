{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.qubix;
  makeVswitch = name: target: {
    interfaces = [];
  };
  makeProxyVM = name: target: {
    name = name;
    autostart = target.autostart;
    config = {config, ...}:
    let
      ovsup = pkgs.writeScript "${name}-ovs-up" ''
        #!${pkgs.stdenv.shell}
        mkdir -p /var/run/qubix/${name}
        ${pkgs.inetutils}/bin/ifconfig $1 up
        ${pkgs.openvswitch}/bin/ovs-vsctl add-port ${name} $1
      '';
      ovsdown = pkgs.writeScript "${name}-ovs-down" ''
        #!${pkgs.stdenv.shell}
        ${pkgs.inetutils}/bin/ifconfig $1 down
        ${pkgs.openvswitch}/bin/ovs-vsctl del-port ${name} $1
      '';
      #sshRedirPort = fixedWidthString 4 "2" (toString number);
    in {
      imports = [ ./xpra.nix ];
      services.xpra = {
        enable = true;
        bind = false;
      };
      virtualisation.memorySize = mkDefault 256;
      virtualisation.graphics = false;
      virtualisation.qemu.options = [
        "-object rng-random,filename=/dev/random,id=rng0 -device virtio-rng-pci,rng=rng0"
        "-virtfs local,path=/var/run/qubix/${name},security_model=none,mount_tag=qubix"
      ];
      fileSystems."/var/run/qubix" = {
        device = "qubix";
        fsType = "9p";
        options = [ "trans=virtio" "version=9p2000.L" ];
      };
      services.openssh.enable = true;
      users.users.root.openssh.authorizedKeys.keyFiles = cfg.sshKeyFiles;
      virtualisation.qemu.networkingOptions = [
        "-netdev type=tap,id=net0,script=${ovsup},downscript=${ovsdown}"
        "-device virtio-net-pci,netdev=net0"
        #"-redir tcp:${sshRedirPort}:22"
      ];
    };
  };
  makeWorkspaceVM = name: target: {
    name = target.name;
    autostart = target.autostart;
    config = {config, ...}:
    let
      ovsup = pkgs.writeScript "${name}-ovs-up" ''
        #!${pkgs.stdenv.shell}
        mkdir -p /var/run/qubix/${name}
        ${pkgs.inetutils}/bin/ifconfig $1 up
        ${pkgs.openvswitch}/bin/ovs-vsctl add-port ${target.proxy} $1
      '';
      ovsdown = pkgs.writeScript "${name}-ovs-down" ''
        #!${pkgs.stdenv.shell}
        ${pkgs.inetutils}/bin/ifconfig $1 down
        ${pkgs.openvswitch}/bin/ovs-vsctl del-port ${target.proxy} $1
      '';
      #sshRedirPort = fixedWidthString 4 "2" (toString number);
    in {
      imports = [ ./xpra.nix ];
      services.xpra = {
        enable = true;
        bind = false;
      };
      virtualisation.memorySize = mkDefault 512;
      virtualisation.graphics = false;
      virtualisation.qemu.options = [
        "-object rng-random,filename=/dev/random,id=rng0 -device virtio-rng-pci,rng=rng0"
        "-virtfs local,path=/var/run/qubix/${name},security_model=none,mount_tag=qubix"
      ];
      fileSystems."/var/run/qubix" = {
        device = "qubix";
        fsType = "9p";
        options = [ "trans=virtio" "version=9p2000.L" ];
      };
      services.openssh.enable = true;
      users.users.root.openssh.authorizedKeys.keyFiles = cfg.sshKeyFiles;
      virtualisation.qemu.networkingOptions = mkIf target.network [
        "-netdev type=tap,id=net0,script=${ovsup},downscript=${ovsdown}"
        "-device virtio-net-pci,netdev=net0"
        #"-redir tcp:${sshRedirPort}:22"
      ];
      #} // target.config;
    };
  };
in {
  imports = [ ./kvms.nix ];
  ######### NixOS Options Interface
  options = {
    qubix = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable the Qubix system";
      };
      sshKeyFiles = mkOption {
        type = types.listOf types.path;
        default = [];
        description = "SSH keys to allow access to the qubix VM's.";
      };
      proxies = mkOption {
        type = types.attrsOf (types.submodule (
          { config, options, name, ... }:
          {
            options = {
              name = mkOption {
                type = types.string;
                default = name;
                description = "Proxy VM name.";
              };
              autostart = mkOption {
                type = types.bool;
                default = false;
                description = "Start this VM on boot.";
              };
            };
          }
        ));
        default = {};
        example = literalExample ''
          {
            wifi = {
              autostart = true;
            };
          }
        '';
        description = ''
          Qubix proxy VM's. These shape the Qubix networks.
        '';
      };
      workspaces = mkOption {
        type = types.attrsOf (types.submodule (
          { config, options, name, ... }:
          {
            options = {
              name = mkOption {
                type = types.string;
                default = name;
                description = "Workspace VM name.";
              };
              autostart = mkOption {
                type = types.bool;
                default = false;
                description = "Start this VM on boot.";
              };
              network = mkOption {
                type = types.bool;
                default = true;
                description = "Setup networking via the given proxy.";
              };
              proxy = mkOption {
                type = types.str;
                description = "Proxy to connect this VM to";
              };
              config = mkOption {
                description = "Nixos config for guest";
                type = lib.mkOptionType {
                  name = "Toplevel NixOS config";
                  merge = loc: defs: (import <nixos/nixos/lib/eval-config.nix> {
                    modules = let extraConfig = {
                      networking.hostName = mkDefault name;
                      virtualisation.graphics = false;
                      virtualisation.diskImage = "/var/lib/qubix/${name}.qcow2";
                    };
                  in [ extraConfig ] ++ (map (x: x.value) defs);
                  prefix = [ "qubix-ws" name ];
                }).config;
              };
            };
          };
        }
        ));
        default = {};
        example = literalExample ''
          {
            database = {
              autostart = true;
              proxy = "ethervm";
            };
          }
        '';
        description = ''
          Qubix workspaces are general use VM's that can use Qubix Proxies for networking.
        '';
      };
    };
  };
  ######### Implementation of the interface's options
  config = let
    vswitches = mapAttrs makeVswitch cfg.proxies;
    proxyVMs = mapAttrs makeProxyVM cfg.proxies;
    workspaceVMs = mapAttrs makeWorkspaceVM cfg.workspaces;
  in mkIf cfg.enable {
    boot.kernelModules = [ "virtio" "tun" ];
    boot.kernel.sysctl = { "net.ipv4.ip_forward" = 1; };
    virtualisation.vswitch.enable = true;
    virtualisation.vswitch.resetOnStart = true;
    kvms.enable = true;

    networking.vswitches = vswitches;
    kvms.vms = proxyVMs // workspaceVMs;
  };
}
