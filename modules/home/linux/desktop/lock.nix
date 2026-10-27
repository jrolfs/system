{ config, lib, osConfig, ... }:

# What locks the screen. The lock screen itself is the shell's (shell/).
#
# hypridle is here for its lock handling only: `loginctl lock-session` (the ⌘Esc
# binding) and suspend both ask logind to lock, and something in the session
# has to answer by telling the shell to lock. There are deliberately no idle
# timeouts, since this machine spends long stretches showing video with nobody
# touching the keyboard.
#
# No running check in front of the call, as hyprlock needed: the shell's lock
# is idempotent, and with the shell down there is nothing to answer it anyway.

lib.mkIf (osConfig.desktop.enable or false) {
  services.hypridle = {
    enable = true;
    settings.general = {
      lock_cmd = "${lib.getExe config.programs.quickshell.package} -c shell ipc call lock lock";
      before_sleep_cmd = "loginctl lock-session";
      after_sleep_cmd = "hyprctl dispatch 'hl.dsp.dpms({ action = \"on\" })'";
    };
  };
}
