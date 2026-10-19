{ inputs, ... }:
{
  imports = [ inputs.stinkpot.homeManagerModules.default ];

  programs.stinkpot.enable = true;
}
