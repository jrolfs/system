#!/usr/bin/env sh

# Set window gap in Moom to 10px
defaults write /Users/jamie/Library/Preferences/com.manytricks.Moom "Grid Spacing: Gap" -int 10

# Switch profile in Hocus Focus
defaults write com.uglyapps.HocusFocus.plist kActiveProfileGUIDKey -string D6DF52CC-F359-42C0-970E-9971246CD8BB
pkill -fl "Hocus Focus"
"/Applications/Hocus Focus.app/Contents/MacOS/Hocus Focus" &

# Remove any old sockets
/bin/ls -1c ~/.local/share/kitty | tail -n+2 | xargs -I _ rm ~/.local/share/kitty/_

# Set font size in Kitty
/usr/local/bin/kitty @ --to unix:$(/run/current-system/sw/bin/fd socket ~/.local/share/kitty) set-font-size 13
