{ ... }:
{
  system.defaults = {
    NSGlobalDomain.AppleFontSmoothing = 0;

    dock = {
      tilesize = 36;
      autohide = true;
      orientation = "left";
      show-recents = false;

      # bottom-right hot corner → Quick Note
      wvous-br-corner = 14;

      # pinned apps, in dock order (left side)
      persistent-apps = [
        "/Applications/Safari.app"
        "/System/Applications/Mail.app"
        "/System/Applications/Calendar.app"
        "/System/Applications/Reminders.app"
        "/Applications/Ghostty.app"
        "/Applications/Discord.app"
        "/Applications/Slack.app"
        "/Applications/Linear.app"
        "/Applications/Notion.app"
        "/Applications/Telegram.app"
      ];

      # folders/stacks (right side)
      persistent-others = [
        "/Users/nikita/Downloads"
      ];
    };

    CustomUserPreferences = {
      NSGlobalDomain = {
        # disable font smoothing
        CGFontRenderingFontSmoothingDisabled = true;
      };
      "com.apple.mail" = {
        # show mail attachments as icons
        DisableInlineAttachmentViewing = true;
      };
      "com.apple.desktopservices" = {
        # avoid creating .DS_Store files on network or USB volumes
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };
      "com.apple.Safari" = {
        # show the Develop menu in the menu bar
        IncludeDevelopMenu = true;
        WebKitDeveloperExtrasEnabledPreferenceKey = true;
        "com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" = true;
      };
    };
  };

  system.activationScripts.postActivation.text = ''
    # disable sonoma language switch bubble
    defaults write /Library/Preferences/FeatureFlags/Domain/UIKit.plist redesigned_text_cursor -dict-add Enabled -bool NO

    # do not launch Music.app when play is pressed
    launchctl unload -w /System/Library/LaunchAgents/com.apple.rcd.plist 2>/dev/null || true
  '';
}
