{ config, ... }:
{
  home.sessionVariables.LEDGER_FILE = "${config.home.homeDirectory}/Developer/finance/main.ledger";
}
