{ config, lib, hostname, ... }:

let
  # A ByHost domain addressed as a path. `defaults` fills in the hardware UUID
  # itself, so the name carries no host suffix and this stays portable.
  byHost = domain:
    "/Users/${config.system.primaryUser}/Library/Preferences/ByHost/${domain}";
in

{
  system.defaults = {
    dock = {
      autohide = true;
      launchanim = true;
      mineffect = "scale";
      minimize-to-application = true;
      mru-spaces = false;
      orientation = "bottom";
      show-process-indicators = true;
      show-recents = false;
      showhidden = true;
      static-only = false;
      tilesize = 48;

      showAppExposeGestureEnabled = true;
      showMissionControlGestureEnabled = true;

      # 1 is the "no action" sentinel, not a real action id — this turns off the
      # Quick Note corner, which otherwise fires whenever the pointer lands in
      # the bottom-right on the way to something else.
      "wvous-br-corner" = 1;

      # Every entry has to exist at activation time or the Dock renders a "?"
      # placeholder tile in its place, so anything listed here needs to be
      # installed unconditionally, not listed in excluded-apps.nix.
      persistent-apps = [
        "/Applications/kitty.app"
        "/Applications/Zed.app"
        "/Applications/Linear.app"
        "/Applications/Obsidian.app"
        "/Applications/Glide.app"
        "/Applications/Glide Developer.app"
        "/Applications/Superhuman.app"
        "/Applications/Telegram.app"
        "/System/Applications/Messages.app"
        "/Applications/WhatsApp.app"
        "/Applications/Slack.app"
        "/Applications/Fantastical.app"
      ];

      persistent-others = [
        "/Users/${config.system.primaryUser}/Images/Screenshots"
        {
          folder = {
            path = "/Users/${config.system.primaryUser}/Downloads";
            arrangement = "date-added";
            showas = "fan";
          };
        }
      ];
    };

    finder = {
      AppleShowAllExtensions = true;
      FXEnableExtensionChangeWarning = false;
      QuitMenuItem = true;

      FXDefaultSearchScope = "SCcf";
      FXPreferredViewStyle = "Nlsv";
      NewWindowTarget = "Home";
      ShowPathbar = true;

      # Item count and free space along the bottom of the window. On both
      # machines already, but the option defaults to false, so a fresh one
      # would come up without it.
      ShowStatusBar = true;

      # What the desktop is allowed to hold. The internal disk is reachable
      # from anywhere and only ever in the way; anything plugged in or mounted
      # is worth an icon precisely because it is temporary.
      CreateDesktop = true;
      ShowHardDrivesOnDesktop = false;
      ShowExternalHardDrivesOnDesktop = true;
      ShowRemovableMediaOnDesktop = true;
      ShowMountedServersOnDesktop = false;
    };

    # The desktop's own view options — Finder's View → Show View Options when
    # the desktop has focus. nix-darwin has no structured option for it because
    # it isn't a flat key: it's one nested dictionary per view style, and a
    # write replaces the whole thing rather than merging into it, so every key
    # Finder expects has to be here (which is why the untouched defaults are
    # spelled out alongside the two settings that aren't).
    #
    # Finder reads this rather than owning it, so the write sticks — but it
    # picks the value up when it next launches, not while it is running. On a
    # fresh machine that means the first login; on a running one, `killall
    # Finder`.
    # Hides the Tags section of Finder's sidebar — Finder Settings → Sidebar →
    # Tags → Recent Tags. Not a nix-darwin option, and the name undersells it:
    # this is the whole section, not just recently-used ones. The separate
    # FavoriteTagNames array is left at its stock colours, since it feeds the
    # right-click Tags menu rather than the sidebar.
    CustomUserPreferences."com.apple.finder".ShowRecentTags = false;

    CustomUserPreferences."com.apple.finder".DesktopViewSettings = {
      GroupBy = "None";

      IconViewSettings = {
        arrangeBy = "dateCreated";
        iconSize = 96.0;
        gridSpacing = 100.0;

        backgroundType = 0;
        backgroundColorRed = 1.0;
        backgroundColorGreen = 1.0;
        backgroundColorBlue = 1.0;
        gridOffsetX = 0.0;
        gridOffsetY = 0.0;
        labelOnBottom = true;
        showIconPreview = true;
        showItemInfo = false;
        textSize = 12.0;
        viewOptionsVersion = 1;
      };
    };

    screencapture.location = "~/Images/Screenshots";

    trackpad = {
      Clicking = true;
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = true;

      # Three-finger vertical swipe has to stay off for three-finger drag to
      # work — they compete for the same gesture.
      TrackpadThreeFingerVertSwipeGesture = 0;

      # Same competition, and the same resolution: with three-finger drag on,
      # a three-finger tap is a drag that started and stopped, not a lookup.
      # Both machines sit at 0 already; the option's default is 2, so this is
      # only about where a fresh machine starts.
      TrackpadThreeFingerTapGesture = 0;
    };

    LaunchServices = {
      LSQuarantine = false;
    };

    # Karabiner maps Fn+HJKL to the arrow keys, so macOS must not claim the Fn
    # key for itself. Requires a restart to take effect.
    hitoolbox.AppleFnUsageType = "Do Nothing";

    menuExtraClock = {
      ShowAMPM = false;
      ShowDate = 2;
      ShowDayOfWeek = false;
    };

    # "Displays have separate Spaces" off: one space spans every display, so a
    # fullscreen window doesn't blank the other monitor.
    spaces.spans-displays = true;

    # universalaccess is deliberately absent. com.apple.universalaccess is
    # TCC-protected, and activation writes it via `launchctl asuser … sudo
    # --user=jamie -- defaults write`, which detaches the write from any process
    # holding Full Disk Access — so it fails with "Could not write domain"
    # regardless of what the terminal is granted. activate runs under `set -e`,
    # so that one failure aborted every remaining step: the rest of the user
    # defaults, the Dock restart, launchd services, the Homebrew bundle and the
    # home-manager activation. Zoom's scroll-gesture toggle is a one-time click
    # in System Settings → Accessibility → Zoom; it is not worth an FDA-granted
    # wrapper binary, which is the only thing that would make the write land.

    # screensaver is deliberately absent too. The picture and the screen saver
    # are two halves of one store now — Desktop and Idle under the same scope in
    # com.apple.wallpaper — and WallpaperAgent owns it, so the module choice
    # (Drift, here) is no more declarable than the wallpaper was; see
    # modules/home/wallpaper.nix, which reaches the wallpaper half through
    # NSWorkspace because that is the only public way in. The legacy
    # com.apple.screensaver keys still exist and are still populated, but they
    # are a mirror the store writes to rather than the thing being read, and
    # they are ByHost, which CustomUserPreferences writes past for the same
    # reason it can't reach the menu bar items below. nix-darwin's two options
    # here (askForPassword, askForPasswordDelay) are about the lock screen, not
    # about which saver runs, and are left at their defaults. Hammerspoon is no
    # help either, which is where the wallpaper half went: hs.caffeinate can
    # start a screen saver and nothing more — there is no API for choosing one
    # or for the idle time before it runs.

    ActivityMonitor.ShowCategory = 100;

    SoftwareUpdate.AutomaticallyInstallMacOSUpdates = true;

    loginwindow = {
      GuestEnabled = false;
      SHOWFULLNAME = false;
    };

    # Stage Manager stays off, and clicking the wallpaper must not shove every
    # window aside to reveal the desktop.
    #
    # The two HideWidgets options are the whole of System Settings → Desktop &
    # Dock → Widgets → "Show widgets", and turning them on is what gets rid of
    # the clock and calendar macOS seeds a new desktop with. It is all or
    # nothing, and it is the only part of widgets that is declarable at all.
    #
    # Which widgets exist and where they sit — on the desktop and in the
    # Notification Center sidebar alike — is not in any defaults domain. It is
    # a row per host in the HostConfigs table of
    # ~/Library/Group Containers/group.com.apple.chronod/chronod/chrono.sql,
    # holding an NSKeyedArchiver graph of ChronoKit objects that carries each
    # widget's app-intent payload. ChronoServices does have a write path for it
    # (CHSWidgetHost -setConfiguration:), but reaching it means holding
    # com.apple.chronoservices and com.apple.private.chrono-extension-host,
    # which a locally signed helper cannot claim. So the sidebar is rebuilt by
    # hand per machine, and the two have drifted: newt carries Fantastical and
    # CARROT Weather large over Batteries and World Clock small, while ala is
    # still on the Calendar/Weather/Photos set macOS ships with.
    WindowManager = {
      AutoHide = false;
      EnableStandardClickToShowDesktop = false;
      AppWindowGroupingBehavior = true;
      HideDesktop = true;
      StageManagerHideWidgets = true;
      StandardHideDesktopIcons = false;
      StandardHideWidgets = true;

      # Holding option while dragging a window snaps it into macOS's own tiling
      # layout, which is on by default and fights Moom and Stay for the same
      # drag. Off on both machines already, undeclared until now.
      EnableTilingOptionAccelerator = false;
    };

    # Menu bar items. system.defaults.controlcenter reaches this domain by
    # writing to the ByHost path, and CustomUserPreferences hands its key to
    # `defaults write` unchanged, so the same path works here — with the whole
    # integer available rather than the bool the module options take, which
    # only ever write 18 or 24.
    #
    # Apple documents none of these integers, but checking them against the
    # items com.apple.controlcenter currently reports as visible pins three of
    # them down. Bluetooth sits at 2 and shows because a device is connected,
    # while Display and Focus sit at 2 and stay hidden; everything at 8 is
    # absent from that list and Sound at 18 is in it.
    #
    # Writing defaults only restarts the Dock, so a change here appears at the
    # next login unless ControlCenter is killed by hand.
    CustomUserPreferences.${byHost "com.apple.controlcenter"} = {
      # 18: always in the menu bar.
      Sound = 18;

      # 2: only while the item has something to say.
      Bluetooth = 2;
      Display = 2;
      FocusModes = 2;

      # 8: Control Center only.
      AirDrop = 8;
      NowPlaying = 8;
      Siri = 8;
      VPN = 8;
      VoiceControl = 8;

      # Screen Mirroring shows, but the GUI wrote 0 rather than the 18 the
      # reading above predicts, so it is copied as-is rather than normalised.
      ScreenMirroring = 0;

      MusicRecognition = 1;
      BatteryShowEnergyMode = 1;
    };

    # Spotlight keeps its menu bar item in its own ByHost domain. Siri's is in
    # an ordinary domain, despite the Control Center module above also carrying
    # a Siri key: that one governs the Control Center tile, this one the menu
    # bar item.
    CustomUserPreferences.${byHost "com.apple.Spotlight"}.MenuItemHidden = true;
    CustomUserPreferences."com.apple.Siri".StatusMenuVisible = false;

    # Third-party menu bar items are not Control Center's to track. AppKit
    # keeps each one in its owning app's own domain, under the status item's
    # autosave name — and an app that never sets one gets "Item-0" by creation
    # order, which holds for these single-item agents but would shift under an
    # app that grew a second. Only hidden items appear: the key is written
    # when something is dragged out of the menu bar, so a visible item has no
    # key at all and nothing to pin.
    #
    # Velja is absent for that same reason: its item is visible, so there is
    # no key. Its domain does sit in an App Store sandbox container rather
    # than in ~/Library/Preferences, but that is no obstacle to writing it.
    # cfprefsd resolves the domain either way, which is what velja.nix relies
    # on.
    CustomUserPreferences."com.apple.TextInputMenuAgent"."NSStatusItem VisibleCC Item-0" =
      false;
    CustomUserPreferences."com.cordlessdog.Stay"."NSStatusItem VisibleCC Item-0" =
      false;
    CustomUserPreferences."org.pqrs.Karabiner-Console-User-Server"."NSStatusItem VisibleCC Item-0" =
      false;

    smb = {
      NetBIOSName = lib.toUpper hostname;
      ServerDescription = config.networking.computerName;
    };

    ".GlobalPreferences"."com.apple.sound.beep.sound" =
      "/System/Library/Sounds/Tink.aiff";

    NSGlobalDomain = {
      "com.apple.mouse.tapBehavior" = 1;
      "com.apple.springing.delay" = 0.0;
      "com.apple.springing.enabled" = true;
      "com.apple.swipescrolldirection" = true;
      "com.apple.trackpad.enableSecondaryClick" = true;
      "com.apple.trackpad.trackpadCornerClickBehavior" = 1;
      AppleFontSmoothing = 0;
      AppleKeyboardUIMode = 3;
      ApplePressAndHoldEnabled = false;
      AppleShowAllExtensions = true;
      AppleShowScrollBars = "WhenScrolling";
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = true;
      NSDisableAutomaticTermination = true;
      NSDocumentSaveNewDocumentsToCloud = false;
      NSNavPanelExpandedStateForSaveMode = true;
      NSNavPanelExpandedStateForSaveMode2 = true;
      NSScrollAnimationEnabled = true;
      NSTableViewDefaultSizeMode = 2;
      NSTextShowsControlCharacters = false;
      NSUseAnimatedFocusRing = true;
      NSWindowResizeTime = 0.01;
      PMPrintingExpandedStateForPrint = true;
      PMPrintingExpandedStateForPrint2 = true;

      AppleICUForce24HourTime = true;
      AppleInterfaceStyle = "Dark";
      AppleWindowTabbingMode = "always";
      "com.apple.keyboard.fnState" = true;
    };
  };

  # Remote Login. Enabled declaratively rather than left to whoever last
  # visited System Settings — provisioning a new machine needs it before there
  # is anyone at the keyboard to turn it on.
  services.openssh.enable = true;

  # On by default on newt, off on a fresh install — a default that points the
  # wrong way is worth pinning even when the value looks unremarkable.
  networking.applicationFirewall = {
    enable = true;
    allowSigned = true;
    allowSignedApp = true;
    enableStealthMode = false;
  };

  time.timeZone = "America/Los_Angeles";

  system.startup.chime = false;

  # systemsetup writes these to both power sources at once, so only the values
  # newt uses for both can move over. Its computer-sleep setting differs by
  # source — never on AC, but not on battery — which this cannot express, so it
  # stays out rather than getting flattened into a laptop that never sleeps.
  power.sleep = {
    display = 45;
    harddisk = 10;
  };
}
