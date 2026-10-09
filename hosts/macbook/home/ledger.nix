{ config, ... }:
{
  home.sessionVariables.LEDGER_FILE = "${config.home.homeDirectory}/Developer/ngalaiko/finance/main.ledger";
}
