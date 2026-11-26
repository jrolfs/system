{ inputs, pkgs, ... }:

# Firefox (release, Developer Edition, Nightly) and Glide are installed by
# Homebrew, in modules/darwin/homebrew.nix, and configured from here. So are the
# Chrome channels, at the bottom, though none of the reasoning below applies to
# them.
#
# Installing them from nix instead was the obvious move and it does not work.
# home-manager's Firefox modules install `wrapFirefox <browser>`, and on darwin
# that wrapper rebuilds the .app as a tree of symlinks and replaces
# CFBundleExecutable with a makeWrapper shim, which leaves the bundle with no
# code signature at all (`codesign -dv` on the wrapped output: "code object is
# not signed"; on the unwrapped one: "Developer ID Application: Robert Craigie
# (M3M9SSHSKB)"). A browser needs that signature for more than Gatekeeper:
#
#   - 1Password's BrowserSupport helper verifies the calling browser's signature
#     and team id, and refuses an unsigned one. That is the
#     "BrowserVerificationFailed" in glide-browser/glide#261, and TouchID unlock
#     in the extension sits downstream of it.
#   - Entitlements live in the signature, including
#     com.apple.developer.web-browser.public-key-credential, which is what makes
#     passkeys work. Glide gained it in 612180e; wrapping throws it away again.
#   - TCC grants (camera, microphone, screen recording, notifications) are keyed
#     on bundle path *and* signing identity, so an unsigned bundle at a store
#     path that changes every version re-prompts forever.
#
# Two of the four aren't packaged for darwin anyway: firefox-devedition-bin and
# firefox-beta-bin were removed from nixpkgs on 2025-06-06 and alias to source
# builds, which are Linux-only, and Nightly has never been in nixpkgs.
#
# None of that costs us any configuration, because on darwin the Mozilla
# enterprise policy engine reads macOS preferences rather than a policies.json
# inside the bundle. nsMacPreferencesReader asks
# `[[NSUserDefaults standardUserDefaults] dictionaryRepresentation]`, so the
# domain is whatever bundle identifier the running app has (hence a separate
# domain per channel below, and Glide reading its own), and the user domain that
# home-manager writes is in that search list. Mozilla documents the
# `sudo defaults write /Library/Preferences/...` form because that is what MDM
# uses, not because the user domain is ignored.

let
  # 1Password's installer writes this manifest to the Firefox location only
  # (~/Library/Application Support/Mozilla/NativeMessagingHosts), so Firefox
  # needs nothing from us. Glide patches nsXREDirProvider to look under
  # "Glide Browser" instead, which is why 1Password can't find it there and why
  # glide-browser/glide#261 ends in a hand-made symlink. glide.nix's module
  # knows that path, so handing it a package is all this takes.
  #
  # allowed_extensions is copied from the manifest 1Password installs; refresh
  # it from
  # ~/Library/Application Support/Mozilla/NativeMessagingHosts/com.1password.1password.json
  # if a 1Password update starts shipping new extension ids.
  onePasswordMessagingHost =
    pkgs.writeTextDir "lib/mozilla/native-messaging-hosts/com.1password.1password.json"
      (builtins.toJSON {
        name = "com.1password.1password";
        description = "1Password BrowserSupport";
        path =
          "/Applications/1Password.app/Contents/Library/LoginItems"
          + "/1Password Browser Helper.app/Contents/MacOS/1Password-BrowserSupport";
        type = "stdio";
        allowed_extensions = [
          "{0a75d802-9aed-41e7-8daa-24c067386e82}"
          "{25fc87fa-4d31-4fee-b5c1-c32a7844c063}"
          "{d634138d-c276-4fc8-924b-40a0ea21d284}"
        ];
      });

  # Everything both Mozilla browsers get. Firefox and Glide are the same engine
  # here, so the policies and the preference names are identical.
  #
  # SearchEngines matches a built-in engine on its display name, and the search
  # config calls the ddg engine "DuckDuckGo". The policy was ESR-only until
  # Firefox 139, which both browsers are past. It runs through
  # runOncePerModification keyed on the value, so it sets the default once
  # rather than re-asserting it at every start. Picking another engine by hand
  # afterwards sticks, and only editing this string moves it again.
  #
  # The prompt is the "Close 3 windows?" dialog from BrowserGlue's quit
  # handler. browser.warnOnQuit is the first thing that handler reads and it
  # returns early, so that one pref is what removes the dialog. The other two
  # sit behind the checkboxes the handler would go on to consult, and are set
  # here so the Settings UI reads as what actually happens. tabs.warnOnClose
  # also covers closing a window rather than quitting, which takes a different
  # path (gBrowser.warnAboutClosingTabs) and reads that pref on its own.
  mozillaPolicies = {
    SearchEngines.Default = "DuckDuckGo";

    Preferences = {
      "browser.warnOnQuit" = {
        Value = false;
        Status = "locked";
      };
      "browser.warnOnQuitShortcut" = {
        Value = false;
        Status = "locked";
      };
      "browser.tabs.warnOnClose" = {
        Value = false;
        Status = "locked";
      };
    };
  };

  # Chrome reads enterprise policy out of its own preferences domain, one key
  # per policy, and classifies anything that isn't force-managed as a
  # *recommended* policy at user scope (policy_loader_mac.mm). That is what we
  # want: the value applies, the UI can still override it, and the "Managed by
  # your organization" menu item stays away, because that needs machine scope.
  # Every key here is can_be_recommended, so a plain user-domain write lands.
  #
  # WarnBeforeQuittingEnabled is the "Warn Before Quitting (⌘Q)" overlay, the
  # one that makes you hold the shortcut down. Mac-only, Chrome 102 and up,
  # where it replaced ConfirmToQuitEnabled.
  #
  # Chrome has no policy for "use the built-in DuckDuckGo entry", so the
  # default engine has to be respecified in full. The URLs are DuckDuckGo's own
  # opensearch.xml.
  chromePolicies = {
    WarnBeforeQuittingEnabled = false;

    DefaultSearchProviderEnabled = true;
    DefaultSearchProviderName = "DuckDuckGo";
    DefaultSearchProviderKeyword = "ddg";
    DefaultSearchProviderSearchURL = "https://duckduckgo.com/?q={searchTerms}";
    DefaultSearchProviderSuggestURL = "https://duckduckgo.com/ac/?q={searchTerms}&type=list";
    DefaultSearchProviderIconURL = "https://duckduckgo.com/favicon.ico";
  };

  # EnterprisePoliciesEnabled on its own applies no policy. It is the switch
  # that has to be on before a domain is read at all, and the two modules below
  # write it into their own domains for the same reason. `about:policies` in a
  # running browser lists what actually took.
  mozillaChannel = mozillaPolicies // {
    EnterprisePoliciesEnabled = true;
  };
in
{
  imports = [ inputs.glide.homeModules.default ];

  # `package = null` is the whole trick: it turns both modules into pure
  # configuration and installs nothing. Everything except `languagePacks` and
  # `pkcs11Modules` still applies (the latter has a policy equivalent,
  # SecurityDevices), and `globalExtensions` keeps working on darwin as long as
  # darwinDefaultsId is set.
  #
  # `profiles` is deliberately not declared, for either browser. The module
  # generates profiles.ini from scratch and emits only [General] and [ProfileN]
  # sections, while the live files carry an [Install<hash>] section
  # ([Install2656FF1E876E9973] for Firefox, [InstallD47AFF610EDBE35B] for Glide)
  # that pins which profile a given *install path* opens. That hash is derived
  # from the app path and has no option here, and it is exactly what gives Glide
  # and Glide Developer their separate profiles. Declaring profiles would drop
  # it, and would make profiles.ini a read-only store symlink that the browser
  # can no longer write back to.
  programs.firefox = {
    enable = true;
    package = null;

    # Replaces a hand-written manifest that pointed at
    # ~/.local/share/tridactyl/native_main (the file on disk was native_main.py)
    # and a vendored copy of tridactyl's old Python messenger whose shebang
    # named /opt/homebrew/bin/python3, which isn't installed. Neither path
    # resolved, so the native messenger had not worked for some time.
    nativeMessagingHosts = [ pkgs.tridactyl-native ];

    policies = mozillaPolicies;
  };

  programs.glide-browser = {
    enable = true;
    package = null;

    # glide.nix doesn't set platforms.darwin.defaultsId, so this defaults to
    # null and policies would be dropped with a warning.
    darwinDefaultsId = "app.glide-browser.glide";

    nativeMessagingHosts = [ onePasswordMessagingHost ];

    policies = mozillaPolicies;
  };

  # The channels that get no module of their own. All three Firefox channels
  # share ~/Library/Application Support/Firefox and a single profiles.ini, so
  # only one programs.firefox instance can exist, but each has its own
  # preferences domain and so can carry its own policies. Glide Developer is
  # here for the same reason: it shares Glide's profile root but is a distinct
  # bundle identifier.
  #
  # The Chrome channels are here rather than in a module because none of
  # home-manager's chromium modules has a policies option. They cover
  # extensions, dictionaries and native messaging hosts, and there is no Canary
  # one at all.
  targets.darwin.defaults = {
    "org.mozilla.firefoxdeveloperedition" = mozillaChannel;
    "org.mozilla.nightly" = mozillaChannel;
    "app.glide-browser.glide.developer" = mozillaChannel;

    "com.google.Chrome" = chromePolicies;
    "com.google.Chrome.beta" = chromePolicies;
    "com.google.Chrome.canary" = chromePolicies;
  };
}
