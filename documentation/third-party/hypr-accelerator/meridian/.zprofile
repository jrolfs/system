# Auto-start Hyprland only on TTY1
#if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
#    exec Hyprland
#fi

# GNOME keyring
eval $(gnome-keyring-daemon --start)

# SSH stuff
#export SSH_AUTH_SOCK

