#
# GPG

function gpgp { echo $1 | gpg-preset-passphrase --preset 91C155A78968EEE863ED8B22626AE770762AC2F3 }

# pinentry-curses has to be told which terminal to draw in. gpg only falls
# back to guessing when this is unset, which is fine interactively and not
# fine anywhere else.
export GPG_TTY=$TTY

# Tell the pinentry dispatcher (modules/home/darwin.nix) that this session has
# a terminal, so it may honour the toggle below. gpg forwards this to the agent
# per invocation, which is the only channel available — by the time pinentry is
# exec'd it has no tty of its own to look at, and the client's real one is sent
# afterwards.
#
# The path is included so the dispatcher can check it: a GUI app launched from
# here inherits this variable, and once the terminal is gone the pty node goes
# with it.
export PINENTRY_USER_DATA=tty=$TTY

# Toggle between the macOS GUI pinentry and the curses one.
#
# gpg-agent execs pinentry-program fresh for every prompt, and what it execs
# is a dispatcher (see modules/home/darwin.nix) that reads this state file. So
# flipping the file takes effect on the very next prompt with no agent reload,
# and gpg-agent.conf stays declarative instead of being rewritten in place —
# which it cannot be anyway, now that it is a read-only store symlink.
#
# Anything that is not "mac" means curses, so no file at all means curses. This
# only decides what *terminal* sessions get; anything without a live terminal
# gets the GUI dialog regardless, since curses has nowhere to draw.
function pin() {
    local state="${XDG_STATE_HOME:-$HOME/.local/state}/pinentry"
    local mode=curses

    [[ -r $state ]] && mode=$(<"$state")

    mkdir -p "${state:h}"

    # >| rather than >: prezto's environment module sets NO_CLOBBER, which would
    # refuse to overwrite the file on every toggle after the first.
    if [[ $mode == mac ]]; then
        print -r -- curses >| "$state"
        echo -ne "\033[1;33m\033[0m Using \033[1mdefault\033[0m pinentry"
    else
        print -r -- mac >| "$state"
        echo -ne "\033[1;33m󰌋\033[0m Using \033[1mmacOS\033[0m pinentry"
    fi
}

