{ config, lib, pkgs, ... }:

# Runs nix-switch in a kitty panel that slides in from the right edge of the
# screen, stays above other windows while the switch runs, and draws a progress
# bar in its tab bar. On success it counts down and slides away; on failure it
# stays, holding a shell, until ctrl+d.
#
# A panel rather than a kitty window because a panel is not an ordinary
# window: it appears on whatever space is current and has no "Assign To → All
# Desktops" for macOS to lose, which is what made the ⌥⇥ kitty window drag
# itself across spaces.
#
# Three things learned the hard way, all of them shaping what follows:
#
# The panel's bundle is LSBackgroundOnly, so it can never be the frontmost
# application and nothing outside it can make it active. What it can do is take
# key status itself when it is revealed, and with the default focus policy it
# does, deactivating whatever you were typing in. It lives at
# `focus-policy=not-allowed`, which reveals it without touching focus, and the
# focus binding switches the policy only for as long as you want to type in it.
#
# kitty reports a panel's `is_focused` as true whether or not it is, so nothing
# here asks it. Whether the panel has focus is inferred from which application
# is frontmost.
#
# background_blur is drawn by macOS behind the window as soon as it is on screen,
# so anything that animates the panel's contents leaves the frosted pane
# standing at its final position. The slide moves the window itself, from
# kitty-panel, which can drive it at a frame rate a shell cannot.

let
  kittyPanel = pkgs.rustTool {
    name = "kitty-panel";
    src = ../../darwin/pkgs/kitty-panel.rs;
  };

  # Window and screen geometry from CoreGraphics and AppKit, through JXA so it
  # needs no permission: window bounds are readable without Screen Recording,
  # only their titles are not. Coordinates are global and top-left origin, as
  # CoreGraphics reports them, with AppKit's bottom-left screen frames turned
  # round to match.
  windows = pkgs.writeText "switch-panel-windows.js" # javascript
    ''
      ObjC.import('AppKit');
      ObjC.import('CoreGraphics');

      function onScreen() {
        var list = ObjC.castRefToObject($.CGWindowListCopyWindowInfo(
          $.kCGWindowListOptionOnScreenOnly | $.kCGWindowListExcludeDesktopElements, 0));
        var out = [];
        for (var i = 0; i < list.count; i++) {
          var d = list.objectAtIndex(i), b = d.objectForKey('kCGWindowBounds');
          out.push({
            owner: ObjC.unwrap(d.objectForKey('kCGWindowOwnerName')),
            pid: ObjC.unwrap(d.objectForKey('kCGWindowOwnerPID')),
            layer: ObjC.unwrap(d.objectForKey('kCGWindowLayer')),
            x: ObjC.unwrap(b.objectForKey('X')), y: ObjC.unwrap(b.objectForKey('Y')),
            w: ObjC.unwrap(b.objectForKey('Width')), h: ObjC.unwrap(b.objectForKey('Height'))
          });
        }
        return out;
      }

      function screens() {
        var all = $.NSScreen.screens, height = all.objectAtIndex(0).frame.size.height, out = [];
        for (var i = 0; i < all.count; i++) {
          var s = all.objectAtIndex(i), f = s.frame, v = s.visibleFrame;
          out.push({
            name: ObjC.unwrap(s.localizedName),
            x: f.origin.x, y: height - f.origin.y - f.size.height, w: f.size.width, h: f.size.height,
            vx: v.origin.x, vy: height - v.origin.y - v.size.height, vw: v.size.width, vh: v.size.height
          });
        }
        return out;
      }

      function run(argv) {
        if (argv[0] === 'bounds') {
          var mine = onScreen().filter(function (w) { return w.pid === Number(argv[1]); })[0];
          return mine ? [mine.x, mine.y, mine.w, mine.h].join(' ') : "";
        }

        // The main kitty: its biggest ordinary-level window. The panel is
        // lined up with it, so it reads as a pane of the same terminal.
        var kitty = onScreen()
          .filter(function (w) { return w.owner === 'kitty' && w.layer === 0; })
          .sort(function (a, b) { return b.w * b.h - a.w * a.h; })[0] || null;

        var all = screens(), screen = all[0];
        if (kitty) {
          var cx = kitty.x + kitty.w / 2, cy = kitty.y + kitty.h / 2;
          screen = all.filter(function (s) {
            return cx >= s.x && cx < s.x + s.w && cy >= s.y && cy < s.y + s.h;
          })[0] || screen;
        }
        return JSON.stringify({ kitty: kitty, screen: screen });
      }
    '';

  switchPanel = pkgs.writeScriptBin "switch-panel" # zsh
    ''
      #!${pkgs.zsh}/bin/zsh -f

      # Run from Hammerspoon as well as from a shell, with nothing on PATH. The
      # caller's own PATH is kept aside for what runs in the panel: the switch
      # needs darwin-rebuild, and the shell left behind after a failure is
      # where you go to look into it.
      caller_path=$PATH
      export PATH=/usr/bin:/bin:/usr/sbin:/sbin

      kitten=/opt/homebrew/bin/kitten
      kitty_panel=${kittyPanel}/bin/kitty-panel
      jq=${lib.getExe pkgs.jq}
      windows=${windows}
      self=''${0:A}

      state=''${XDG_STATE_HOME:-$HOME/.local/state}/switch-panel
      socket=$state/panel.sock
      address=unix:$socket

      # The panel's own look. Starts from kitty.conf, so the font and theme
      # match the main kitty; these are only what differs.
      opacity=0.7
      blur=64
      width_fraction=0.6
      slide_in_ms=220
      slide_out_ms=180
      countdown=10

      rc() { $kitten @ --to $address "$@" >/dev/null 2>&1 }

      alive() { [[ -S $socket ]] && $kitten @ --to $address ls >/dev/null 2>&1 }

      # The panel's own binary, not just anything mentioning the instance
      # group: a shell whose command line happens to contain this script would
      # match that too, and close_panel kills what this returns.
      panel_pid() {
        pgrep -f 'kitty-quick-access\.app/Contents/MacOS/kitty-quick-access .*--instance-group=switch-panel' | head -1
      }

      frontmost() {
        lsappinfo info -only bundleid "$(lsappinfo front)" 2>/dev/null | sed -n 's/.*="\(.*\)"/\1/p'
      }

      # The tab title is three parts, a label, a middle and a right-hand part,
      # split on U+2063 so the template can colour each: a title is plain text,
      # and colour only comes from the template. kitty-panel's progress bar
      # writes the same shape. The middle is the dim one, bright black, which
      # is what keeps the bar a texture rather than a loading bar.
      #
      # The logo is nf-linux-nixos, built from its codepoint rather than written
      # into this file: a private-use character is exactly what tools pass
      # through by silently dropping it, which is how the first try at this
      # went.
      separator=$'\u2063'
      logo=$'\uf313'
      # Two separators appended, so there are always three parts to index even
      # in a title nothing here set.
      part() { print -r -- "(title+'$separator$separator').split('$separator')[$1]" }
      template="  {fmt.fg.color4}$logo  {fmt.fg.tab}{$(part 0)}{fmt.fg.color8}{$(part 1)}{fmt.fg.tab}{$(part 2)}"

      # Cells the template puts in front of the title: margin, logo, gap.
      prefix=5

      # One big tab, padded to the room the template leaves so it fills the
      # bar, the same as kitty-panel's progress bar does.
      title() {
        local text="switch  $separator$1$separator''${2:+  $2}"
        rc set-tab-title "''${(r:$(( $(columns) - prefix )):: :)text}"
      }

      # The tab bar holds fewer cells than the window has columns: it loses its
      # side margins, and the logo is drawn two cells wide across the space
      # after it. A title any longer is cut short with an ellipsis, which takes
      # the clock off the end of the progress bar, so this leaves room to spare.
      columns() {
        local count=$($kitten @ --to $address ls 2>/dev/null | $jq '.[0].tabs[0].windows[0].columns')
        print -r -- $(( ''${count:-80} - 9 ))
      }

      clock() { printf '%d:%02d' $(( $1 / 60 )) $(( $1 % 60 )) }

      # Positions in the panel kitten's margin space, which is global screen
      # coordinates shifted by whatever the calibration in `run` measured.
      geometry() { read visible offscreen offset < $state/geometry }

      slide_in() { geometry && $kitty_panel slide in $address $offscreen $visible $slide_in_ms }
      slide_out() { geometry && $kitty_panel slide out $address $visible $offscreen $slide_out_ms }

      # On screen and in place, as opposed to hidden or parked off the right
      # edge. Read from the window's real position, not remembered, so a panel
      # moved by anything else is still judged right.
      showing() {
        geometry || return 1
        local -a bounds=(''${=$(osascript -l JavaScript $windows bounds $(panel_pid))})
        (( ''${#bounds} )) && (( bounds[1] - offset < offscreen - 1 ))
      }

      # Hands keyboard focus back to the application it was taken from, and
      # puts the panel back to not being able to take it.
      release_focus() {
        [[ -e $state/focused ]] || return 0
        open -b "$(<$state/focused)"
        rc resize-os-window --action os-panel --incremental focus-policy=not-allowed
        rm -f $state/focused
      }

      close_panel() {
        local pid=$(panel_pid)
        release_focus
        [[ -n $pid ]] && kill $pid 2>/dev/null
        rm -f $socket
      }

      run() {
        close_panel
        mkdir -p $state
        rm -f $state/{status,outcome,interacted,focused,geometry}

        local layout=$(osascript -l JavaScript $windows geometry)
        local -A s
        s=(''${(@f)"$($jq -r '.screen | to_entries[] | .key, (.value | tostring)' <<< $layout)"})

        local x y width height
        if [[ $($jq '.kitty' <<< $layout) != null ]]; then
          local -A k
          k=(''${(@f)"$($jq -r '.kitty | to_entries[] | .key, (.value | tostring)' <<< $layout)"})
          width=$(( s[w] * $width_fraction ))
          x=$(( k[x] + k[w] - width ))
          y=$k[y]
          height=$k[h]
        else
          # No main kitty to line up with: a Moom-zoomed window's edges stand
          # in for it.
          local gap=$(defaults read com.manytricks.Moom 'Grid Spacing: Gap' 2>/dev/null || print 0)
          width=$(( s[w] * $width_fraction ))
          x=$(( s[vx] + s[vw] - gap - width ))
          y=$(( s[vy] + gap ))
          height=$(( s[vh] - 2 * gap ))
        fi
        width=''${width%.*} x=''${x%.*} y=''${y%.*} height=''${height%.*}
        local parked=$(( s[x] + s[w] ))

        # Carried into the panel: where to run from, so nix-switch still finds
        # the worktree it was run in, and a marker that stops the nix-switch in
        # there handing off to yet another panel.
        export SWITCH_PANEL=1 SWITCH_PANEL_DIRECTORY=$PWD SWITCH_PANEL_PATH=$caller_path

        # In a session of its own. Left in this one, the panel shares the
        # process group of whatever ran nix-switch, and went down with it the
        # moment the switch returned, before the countdown it exists to show.
        # The kitten's own --detach would do this, but its re-exec rejects
        # --lines. macOS has no setsid command; perl has POSIX::setsid.
        /usr/bin/perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die "exec: $!"' \
          $kitten panel --edge=none --output-name="$s[name]" \
          --columns=''${width}px --lines=''${height}px --margin-left=$parked --margin-top=$y \
          --layer=overlay --focus-policy=not-allowed --start-as-hidden \
          --single-instance --instance-group=switch-panel --listen-on=$address \
          -o macos_ns_window_layer=NSFloatingWindowLevel \
          -o background_opacity=$opacity -o background_blur=$blur \
          -o allow_remote_control=socket-only -o startup_session=none \
          -o custom_shaders=switch-panel \
          -o tab_bar_edge=top -o tab_bar_min_tabs=1 -o tab_bar_style=separator \
          -o 'tab_separator=""' -o "tab_title_template=$template" -o "active_tab_title_template=$template" \
          -o tab_bar_background=none -o tab_bar_margin_color=none \
          -o active_tab_background='#32302f' -o active_tab_foreground='#c5b18d' -o active_tab_font_style=normal \
          -o 'tab_bar_margin_height=5 3' -o tab_bar_margin_width=10 \
          $self inner "$@" </dev/null >|$state/panel.log 2>&1 &!

        local tries
        for (( tries = 0; tries < 50; tries++ )); do alive && break; sleep 0.1; done
        if ! alive; then
          print -u2 "switch-panel: the panel did not start, see $state/panel.log"
          return 70
        fi

        # Revealed while still parked off the edge, which with focus-policy
        # not-allowed leaves focus where it was. It has to be on screen for
        # CoreGraphics to report it, and the report is what calibrates it:
        # kitty adds its window padding to the size asked for, and the margins
        # are relative to the screen it is on rather than global.
        rc resize-os-window --action show
        local -a actual
        for (( tries = 0; tries < 20; tries++ )); do
          actual=(''${=$(osascript -l JavaScript $windows bounds $(panel_pid))})
          (( ''${#actual} )) && break
          sleep 0.1
        done
        local offset=$(( actual[1] - parked ))
        rc resize-os-window --action os-panel --incremental \
          columns=$(( width - (actual[3] - width) ))px lines=$(( height - (actual[4] - height) ))px \
          margin-top=$(( y - (actual[2] - y) ))
        print -r -- "$(( x - offset )) $(( parked - offset )) $offset" > $state/geometry

        slide_in

        print -u2 "nix-switch: running in the side panel · Hyper+| show/hide · Hyper+Return focus"

        # Ctrl+C here reaches the switch over there.
        trap 'rc signal-child SIGINT' INT

        until [[ -e $state/status ]]; do
          alive || { print -u2 "switch-panel: the panel closed before the switch finished"; return 70 }
          sleep 0.25
        done
        return $(<$state/status)
      }

      inner() {
        cd "''${SWITCH_PANEL_DIRECTORY:-$HOME}"
        export PATH=''${SWITCH_PANEL_PATH:-$PATH}

        $kitty_panel progress $address $(( $(columns) - prefix )) switch &!
        local ticker=$!

        local start=$SECONDS
        "$@"
        local code=$?
        kill $ticker 2>/dev/null
        local took=$(clock $(( SECONDS - start )))

        print -r -- $code > $state/status

        if (( code == 0 )); then
          print -r -- success > $state/outcome
          local left
          for (( left = countdown; left > 0; left-- )); do
            [[ -e $state/interacted ]] && break
            title "✓ done in $took  ·  closing in ''${left}s"
            sleep 1
          done

          if [[ ! -e $state/interacted ]]; then
            slide_out
            exit 0
          fi
          title "✓ done in $took  ·  Hyper+| to close"
        else
          print -r -- failure > $state/outcome
          title "✗ failed (exit $code) after $took  ·  ctrl+d to close"
        fi

        # Stays until ctrl+d, which ends this shell and with it the panel. A
        # login shell, as every other kitty window here starts one.
        exec zsh --login -i
      }

      # Hyper+|: in if it is out, out if it is in. A successful switch you
      # looked at closes on the way out, since there is nothing left to come
      # back to; a failed one only hides, keeping its shell for ctrl+d.
      toggle() {
        alive || return 0

        if showing; then
          release_focus
          slide_out
          if [[ $(<$state/outcome 2>/dev/null) == success ]]; then
            close_panel
          else
            rc resize-os-window --action hide
          fi
        else
          rc resize-os-window --action show
          slide_in
        fi
      }

      # Hyper+Return: into the panel, and a second press back out again.
      #
      # The panel has focus if this gave it focus and the application it was
      # taken from has not been made frontmost since. That is a guess, since
      # kitty cannot be asked, and it is wrong in one direction: leave the panel
      # for some third application and the next press hands focus back rather
      # than taking it.
      focus() {
        alive || return 0

        local front=$(frontmost)
        if [[ -e $state/focused && $front != $(<$state/focused) ]]; then
          release_focus
          return
        fi

        print -r -- $front > $state/focused
        touch $state/interacted

        showing || { rc resize-os-window --action show; slide_in }

        # The panel takes key status when it is revealed, and only then, so it
        # is hidden and revealed again once its policy allows it.
        rc resize-os-window --action os-panel --incremental focus-policy=on-demand
        rc resize-os-window --action hide
        rc resize-os-window --action show
      }

      case $1 in
        run) shift; [[ $1 == -- ]] && shift; run "$@" ;;
        inner) shift; inner "$@" ;;
        toggle) toggle ;;
        focus) focus ;;
        *)
          print -u2 "usage: switch-panel run -- <command...> | toggle | focus"
          exit 64
          ;;
      esac
    '';
in
{
  home.packages = [ switchPanel ];

  # Only from a terminal someone is watching. Not from inside the panel, whose
  # own nix-switch must run there rather than open another; not over SSH, where
  # the panel would slide out onto a screen nobody is in front of; and not
  # without a terminal, where whatever ran it wants the output itself.
  nixCommands.delegate = # zsh
    ''
      if [[ -z $SWITCH_PANEL && -z $SSH_CONNECTION && -t 0 && -t 1 ]] \
        && (( ! ''${argv[(I)--here]} )); then
        ${switchPanel}/bin/switch-panel run -- nix-switch "$@"
        return
      fi
    '';

  # Consumed here so it never reaches darwin-rebuild; the delegate above has
  # already acted on it by the time the arguments are read.
  nixCommands.flags = [
    { pattern = "--here"; action = ":"; description = "run in this terminal instead of the side panel"; }
  ];

  # Generated rather than kept in the dotfiles tree so the bindings run this
  # build of switch-panel by its store path: Hammerspoon starts tasks with no
  # PATH worth the name. The Hyper chords live here rather than in Karabiner
  # because Karabiner's rules do not chain, so none of them can match the Hyper
  # that its own right-option rule synthesises.
  home.file.".hammerspoon/modules/switch-panel.lua".text = # lua
    ''
      local _ = require('modules.utilities')

      local function run(command)
        hs.task.new('${switchPanel}/bin/switch-panel', nil, { command }):start()
      end

      -- Hyper is shift as well as ctrl, option and command, so this is Hyper+|.
      _.bindHyper('\\', function() run('toggle') end)
      _.bindHyper('return', function() run('focus') end)
    '';
}
