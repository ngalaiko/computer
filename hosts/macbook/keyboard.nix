_:
let
  # WebKit text views (Safari, Mail, web views) keep their own copies
  webkitNoAutocorrect = {
    WebAutomaticSpellingCorrectionEnabled = false;
    WebAutomaticTextReplacementEnabled = false;
    WebAutomaticQuoteSubstitutionEnabled = false;
    WebAutomaticDashSubstitutionEnabled = false;
    WebAutomaticLinkDetectionEnabled = false;
  };
in
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

  system.defaults.CustomUserPreferences.NSGlobalDomain = webkitNoAutocorrect // {
    # disable inline typing suggestions
    NSAutomaticTextCompletionEnabled = false;
    # disable automatic text replacement
    NSAutomaticTextReplacementEnabled = false;
    # empty the text-replacement (shortcuts) list
    NSUserDictionaryReplacementItems = [ ];
  };

  system.defaults.CustomUserPreferences."com.apple.Safari" = webkitNoAutocorrect;
  system.defaults.CustomUserPreferences."com.apple.mail" = webkitNoAutocorrect;

  system.defaults.CustomUserPreferences."com.apple.TextEdit" = {
    CorrectSpellingAutomatically = false;
    SmartQuotes = false;
    SmartDashes = false;
    SmartLinks = false;
    TextReplacement = false;
  };

  system.defaults.CustomUserPreferences."com.apple.messageshelper.MessageController".SOInputLineSettings =
    {
      automaticEmojiSubstitutionEnablediMessage = false;
      automaticQuoteSubstitutionEnabled = false;
      automaticSpellingCorrectionEnabled = false;
    };

  # enabled input sources: U.S. + Russian keyboard layouts
  system.defaults.CustomUserPreferences."com.apple.HIToolbox".AppleEnabledInputSources = [
    {
      InputSourceKind = "Keyboard Layout";
      "KeyboardLayout ID" = 0;
      "KeyboardLayout Name" = "U.S.";
    }
    {
      "Bundle ID" = "com.apple.CharacterPaletteIM";
      InputSourceKind = "Non Keyboard Input Method";
    }
    {
      InputSourceKind = "Keyboard Layout";
      "KeyboardLayout ID" = 19456;
      "KeyboardLayout Name" = "Russian";
    }
    {
      "Bundle ID" = "com.apple.PressAndHold";
      InputSourceKind = "Non Keyboard Input Method";
    }
  ];

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
