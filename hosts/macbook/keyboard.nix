{ ... }:
{
  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToControl = true;
  };

  # disable everything that rewrites typed text
  system.defaults.NSGlobalDomain = {
    NSAutomaticCapitalizationEnabled = false;
    NSAutomaticSpellingCorrectionEnabled = false;
    NSAutomaticPeriodSubstitutionEnabled = false;
    NSAutomaticDashSubstitutionEnabled = false;
    NSAutomaticQuoteSubstitutionEnabled = false;
    NSAutomaticInlinePredictionEnabled = false;
  };

  system.defaults.CustomUserPreferences.NSGlobalDomain = {
    # disable inline typing suggestions
    NSAutomaticTextCompletionEnabled = false;
    # empty the text-replacement (shortcuts) list
    NSUserDictionaryReplacementItems = [ ];
  };

  system.defaults.CustomUserPreferences."com.apple.symbolichotkeys".AppleSymbolicHotKeys = {
    # Select the previous input source — remapped to Cmd+Space.
    "60" = {
      enabled = true;
      value = {
        type = "standard";
        parameters = [
          32
          49
          1048576
        ];
      };
    };
    # Select next source in Input menu (Ctrl+Option+Space) — disabled.
    "61" = {
      enabled = false;
      value = {
        type = "standard";
        parameters = [
          32
          49
          786432
        ];
      };
    };
    # Spotlight search (Cmd+Space) — disabled.
    "64" = {
      enabled = false;
      value = {
        type = "standard";
        parameters = [
          32
          49
          1048576
        ];
      };
    };
    # Spotlight Finder window search (Cmd+Option+Space) — disabled.
    "65" = {
      enabled = false;
      value = {
        type = "standard";
        parameters = [
          32
          49
          1572864
        ];
      };
    };
  };
}
