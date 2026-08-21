{ ... }:
{
  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToControl = true;
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
