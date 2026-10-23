#
# GPG

function gpgp { echo $1 | gpg-preset-passphrase --preset 91C155A78968EEE863ED8B22626AE770762AC2F3 }

# pinentry-curses has to be told which terminal to draw in. gpg only falls
# back to guessing when this is unset, which is fine interactively and not
# fine anywhere else.
export GPG_TTY=$TTY

# Tell the pinentry dispatcher (modules/home/darwin/default.nix) that this session has
# a terminal, so it may honour the toggle below. gpg forwards this to the agent
# per invocation, which is the only channel available — by the time pinentry is
# exec'd it has no tty of its own to look at, and the client's real one is sent
# afterwards.
#
# The path is included so the dispatcher can check it: a GUI app launched from
# here inherits this variable, and once the terminal is gone the pty node goes
# with it.
export PINENTRY_USER_DATA=tty=$TTY

# Taken over from prezto's gpg module, which is no longer loaded because it
# also loads prezto's ssh module. That one repointed SSH_AUTH_SOCK at a shared
# symlink aimed at whichever agent the most recent shell had, so one local
# shell broke the forwarded agent under every SSH session (and with it sudo by
# SSH key), and it ran `ssh-add` on any agent holding no keys, which is how
# gpg-agent came to ask for a passphrase for the bootstrap's SSH key.
#
# Started here because on Linux the agent's SSH socket exists only while it
# runs, and nothing else starts it before the first ssh.
#
# Only when its socket is missing: gpgconf costs a third of a second, which
# every new shell paid when this ran unconditionally.
[[ -S ${GNUPGHOME:-$HOME/.gnupg}/S.gpg-agent ]] || gpgconf --launch gpg-agent 2> /dev/null

# A prompt for the SSH key has no gpg client to say which terminal it came
# from, so the agent draws it on the terminal it last heard about. Telling it
# before each command keeps that the one in use.
autoload -Uz add-zsh-hook
function _gpg-agent-update-tty {
    gpg-connect-agent UPDATESTARTUPTTY /bye > /dev/null 2>&1
}
add-zsh-hook preexec _gpg-agent-update-tty

# Toggle between the macOS GUI pinentry and the curses one.
#
# gpg-agent execs pinentry-program fresh for every prompt, and what it execs
# is a dispatcher (see modules/home/darwin/default.nix) that reads this state file. So
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

