{ config, lib, pkgs, utils, ... }:

with lib;

let

  bootFs = filterAttrs (n: fs: (fs.fsType == "bcachefs") && (utils.fsNeededForBoot fs)) config.fileSystems;

  commonFunctions = ''
    prompt() {
      local name="$1"
      printf "enter passphrase for $name: "
    }
    tryUnlock() {
      local name="$1"
      local path="$2"
      if bcachefs unlock -c $path > /dev/null 2> /dev/null; then
        prompt $name
        until bcachefs unlock $path 2> /dev/null; do                # repeat until sucessfully unlocked
          printf "unlocking failed!\n"
          prompt $name
        done
        printf "unlocking successful.\n"
      fi
    }
  '';

  openCommand = name: fs: 
    let
      # we need only unlock one device manually, and cannot pass multiple at once
      # remove this attempt when mounting by filesystem uuid is added to bcachefs
      # also, implement automatic waiting for the constituent devices when that happens
      firstDevice = head (splitString ":" fs.device);
    in
      ''
        tryunlock ${name} ${fs.device}
        tryunlock ${name} ${firstDevice}
      '';

in

{
  config = mkIf (elem "bcachefs" config.boot.supportedFilesystems) (
      mkMerge [
        {
          system.fsPackages = [ pkgs.bcachefs-tools ];

          # use kernel package with bcachefs support until it's in mainline
          boot.kernelPackages = pkgs.linuxPackages_testing_bcachefs;
        }

        (mkIf ((elem "bcachefs" config.boot.initrd.supportedFilesystems) || (bootFs != {}))
        {
          boot.initrd.availableKernelModules = [ "bcachefs" "chacha20" "poly1305" ]; # the cryptographic modules are required only for decryption attempts

          boot.initrd.extraUtilsCommands = ''
            copy_bin_and_libs ${pkgs.bcachefs-tools}/bin/bcachefs
          '';
          boot.initrd.extraUtilsCommandsTest = ''
            $out/bin/bcachefs version
          '';

          boot.initrd.postDeviceCommands = commonFunctions + concatStrings (mapAttrsToList openCommand bootFs);
        }
      )
    ]
  );
}
