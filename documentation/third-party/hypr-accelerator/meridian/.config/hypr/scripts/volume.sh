#!/bin/bash
iDIR="$HOME/.config/swaync/icons"
sDIR="$HOME/.config/hypr/scripts"

# ---------- Volume helpers ----------
get_volume_num() { pamixer --get-volume; }                     # numeric only
is_muted() { pamixer --get-mute | grep -q true; }              # returns 0 if muted

get_volume_label() {
    if is_muted; then
        printf "Muted"
    else
        printf "%s%%" "$(get_volume_num)"
    fi
}

get_icon() {
    if is_muted; then
        echo "$iDIR/volume-mute.png"
    else
        v="$(get_volume_num)"
        if   (( v <= 30 )); then echo "$iDIR/volume-low.png"
        elif (( v <= 60 )); then echo "$iDIR/volume-mid.png"
        else                     echo "$iDIR/volume-high.png"
        fi
    fi
}

notify_user() {
    # Keep notification height stable by ALWAYS sending int:value as a number
    local val label
    if is_muted; then
        val=0
    else
        val="$(get_volume_num)"
    fi
    label="$(get_volume_label)"
    notify-send -e \
      -h string:x-canonical-private-synchronous:osd \
      -u low \
      -i "$(get_icon)" \
      "Volume" "$label"
}

# ---------- Volume controls ----------
inc_volume() {
    if is_muted; then
        toggle_mute
    else
        pamixer -i 5 --allow-boost --set-limit 150
        notify_user
    fi
}

dec_volume() {
    if is_muted; then
        toggle_mute
    else
        pamixer -d 5
        notify_user
    fi
}

toggle_mute() {
    if is_muted; then
        pamixer -u
    else
        pamixer -m
    fi
    notify_user
}

# ---------- Microphone helpers ----------
is_mic_muted() { pamixer --default-source --get-mute | grep -q true; }
get_mic_num() { pamixer --default-source --get-volume; }

get_mic_label() {
    if is_mic_muted; then
        printf "Muted"
    else
        printf "%s%%" "$(get_mic_num)"
    fi
}

get_mic_icon() {
    if is_mic_muted; then
        echo "$iDIR/microphone-mute.png"
    else
        echo "$iDIR/microphone.png"
    fi
}

notify_mic_user() {
    local val label
    if is_mic_muted; then
        val=0
    else
        val="$(get_mic_num)"
    fi
    label="$(get_mic_label)"
    # Use a DIFFERENT synchronous tag so mic & volume don't replace each other
    notify-send -e \
      -h int:value:"$val" \
      -h string:x-canonical-private-synchronous:mic_notif \
      -u low \
      -i "$(get_mic_icon)" \
      "Microphone" "$label"
}

# ---------- Microphone controls ----------
toggle_mic() {
    if is_mic_muted; then
        pamixer --default-source -u
    else
        pamixer --default-source -m
    fi
    notify_mic_user
}

inc_mic_volume() {
    if is_mic_muted; then
        toggle_mic
    else
        pamixer --default-source -i 5
        notify_mic_user
    fi
}

dec_mic_volume() {
    if is_mic_muted; then
        toggle_mic
    else
        pamixer --default-source -d 5
        notify_mic_user
    fi
}

# ---------- CLI ----------
case "$1" in
  --get)             get_volume_label ;;
  --inc)             inc_volume ;;
  --dec)             dec_volume ;;
  --toggle)          toggle_mute ;;
  --toggle-mic)      toggle_mic ;;
  --get-icon)        get_icon ;;
  --get-mic-icon)    get_mic_icon ;;
  --mic-inc)         inc_mic_volume ;;
  --mic-dec)         dec_mic_volume ;;
  *)                 get_volume_label ;;
esac

