#!/bin/bash

# ┏━ ┛┏━┛┃ ┃━┏┛  ┏┏ ┏━┃┏━ ┏━┛
# ┃ ┃┃┃ ┃┏━┃ ┃   ┃┃┃┃ ┃┃ ┃┏━┛
# ┛ ┛┛━━┛┛ ┛ ┛   ┛┛┛━━┛━━ ━━┛

# Check if wlsunset is already running
if pgrep -x "wlsunset" > /dev/null; then
    # Kill wlsunset if it's running (switch to day mode)
    killall -9 wlsunset
    notify-send "Night Light" "Off" -u "low"
else
    # Start wlsunset for night mode
    wlsunset -t 3500 &
    notify-send "Night Light" "On" -u "low"
fi

