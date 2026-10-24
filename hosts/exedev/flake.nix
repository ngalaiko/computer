{
  description = "exe.dev with Rex";

  inputs = {
    computer.url = "path:../..";
    rex.url = "https://pkgs.superlogical.com/rex/nix/snapshot.tar.gz";
  };

  outputs = { computer, rex, ... }: {
    nixosConfigurations.exedev = computer.lib.exedevFor {
      extraInputs = { inherit rex; };
      extraModules = [ ./rex.nix ];
    };
  };
}
