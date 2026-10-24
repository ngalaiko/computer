{
  description = "MacBook with Encore";

  inputs = {
    computer.url = "path:../..";
    encore-agents-setup = {
      url = "git+ssh://git@github.com/encoredev/agents-setup";
      flake = false;
    };
  };

  outputs = { computer, encore-agents-setup, ... }: {
    darwinConfigurations.macbook = computer.lib.macbookFor {
      extraInputs = { inherit encore-agents-setup; };
      extraModules = [ ./encore.nix ];
    };
  };
}
