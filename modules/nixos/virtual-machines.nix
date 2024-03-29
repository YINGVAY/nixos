{ config, lib, pkgs, writeText, ... }:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    mkMerge
    ;
  createFile = item: writeText "${item.name}.xml" "Thi is the content for ${item.name}";
  buildvms = lib.concatMapStringsSep "\n" createFile cfg.virtualmachines;



  cfg = config.base.virtualisation;
in
rec {
  options.base.virtualisation = {
    enable = mkEnableOption "virtualisation";

    cpuarch = mkOption { type = types.enum [ "intel" "amd" ]; };

    acspatch = mkEnableOption "acspatch";

    hostcpus = mkOption {
        type=types.string;
    };

    virtcpus = mkOption {
        type=types.string;
    };

    vfioids = mkOption {
      type = types.listOf types.str;
      default = [
       # Get these using lspci -nn

       # TEMPLATE OPTIONS
       # "10de:1b81"
       # "10de:10f0"
      ];
    };
  };
 
  config = mkIf cfg.enable {
    virtualisation = {
      docker.enable = true;
      libvirtd.enable = true;
      spiceUSBRedirection.enable = true;
    };

    programs.dconf.enable = true;

    environment.systemPackages = with pkgs; [
      virt-manager
      qemu
      looking-glass-client
    ];

    systemd.tmpfiles.rules =
    let
      myScript = pkgs.writeScript "qemu-hook.sh" ''
        #!/run/current-system/sw/bin/bash
        if [[ $2 == "start" || $2 == "stopped" ]]
        then
          if [[ $2 == "start" ]]
          then
            systemctl set-property --runtime -- user.slice AllowedCPUs=${cfg.virtcpus}
            systemctl set-property --runtime -- system.slice AllowedCPUs=${cfg.virtcpus}
            systemctl set-property --runtime -- init.scope AllowedCPUs=${cfg.virtcpus}
          else
            systemctl set-property --runtime -- user.slice AllowedCPUs=${cfg.hostcpus}
            systemctl set-property --runtime -- system.slice AllowedCPUs=${cfg.hostcpus}
            systemctl set-property --runtime -- init.scope AllowedCPUs=${cfg.hostcpus}
          fi
        fi
      '';
    in
    [ "L+ /var/lib/libvirt/hooks/qemu - - - - ${myScript}" ];

    boot = {
      kernelParams = mkMerge [
        [
          "iommu=pt"
          (mkIf cfg.acspatch "pcie_acs_override=downstream,multifunction")
          "kvm.ignore_msrs=1"
          "vfio-pci.ids=${builtins.concatStringsSep "," cfg.vfioids}"
          "${cfg.cpuarch}_iommu=on"
        ]
      ];

      kernelModules = [ 
        "kvm-${cfg.cpuarch}"
      ];
    };
  };
}
