{ ... }:
{
  imports = [
    ./claude.nix
  ];

  home.file.".config/AGENTS.md".text = ''
    	<version_control>
    	- always use jujutsu
    	- never user git
    	- never push to remote
    	</version_control>
  '';
}
