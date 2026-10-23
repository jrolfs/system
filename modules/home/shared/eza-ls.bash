# `ls` in an interactive shell is aliased to this. It translates the ls flags
# people actually type into eza's, and hands anything it can't translate to
# the real ls instead of failing: output that isn't a terminal, long options,
# unmapped short flags, and options written after a path. Scripts and LLM tool
# shells read ls's output format, and an eza listing or an "unsupported option"
# error breaks them in ways that are hard to trace back to an alias.
#
# Adapted from https://gist.github.com/eggbean/74db77c4f6404dd1f975bd6f048b86f8

# '0' for output like ls, '1' for eza's defaults.
dot=1 # -a hides . and .. (use -a twice in eza to show them)
hru=1 # human-readable sizes
fgp=0 # group column
lnk=0 # hardlinks column

rev=0
git=0

usage() {
  cat <<EOF
  ls through eza. Options:
   -a  all
   -A  almost all
   -1  one file per line
   -k  bytes
   -h  human readable file sizes
   -F  classify
   -R  recurse
   -r  reverse
   -d  don't list directory contents
   -G  group directories first *
   -I  ignore [GLOBS]
   -i  show inodes
   -S  sort by file size
   -t  sort by modified time
   -u  sort by accessed time
   -U  sort by created time *
   -X  sort by extension
   -T  tree *
   -L  level [DEPTH] *
   -s  file system blocks
   -g  git status of files *
   -x  list by lines, not columns

    * not used in ls

  Anything else runs the system ls, as does any ls whose output isn't a
  terminal. \\ls skips this entirely.
EOF
  exit
}

# exec, so the real ls's exit status and output are exactly what the caller
# gets. It's whatever ls follows on PATH, since this script's own PATH only adds
# eza and git ahead of the caller's: GNU ls on Linux, BSD ls on macOS.
system_ls() {
  exec ls "$@"
}

[[ -t 1 ]] || system_ls "$@"

fallback() {
  printf 'ls: %s has no eza equivalent; running the system ls\n' "$1" >&2
  system_ls "${original[@]}"
}

original=("$@")

# Long options, by name. getopts would see `--color=auto` as the flag '-' and
# make for a confusing message.
for argument in "$@"; do
  case $argument in
    --help) usage ;;
    --) break ;;
    --*) fallback "${argument%%=*}" ;;
  esac
done

eza_opts=()

while getopts ':aAt1lFRrdI:iTkL:suUSghxXG' arg; do
  case $arg in
    a)
      if ((dot == 1)); then eza_opts+=(-a); else eza_opts+=(-a -a); fi
      ;;
    A) eza_opts+=(-a) ;;
    # ls sorts these newest or largest first, eza the other way round, so each
    # counts as a reversal and -r cancels it.
    t) eza_opts+=(-s modified) && rev=$((rev + 1)) ;;
    u) eza_opts+=(-us accessed) && rev=$((rev + 1)) ;;
    U) eza_opts+=(-Us created) && rev=$((rev + 1)) ;;
    S) eza_opts+=(-s size) && rev=$((rev + 1)) ;;
    G) eza_opts+=(--group-directories-first) ;;
    r) rev=$((rev + 1)) ;;
    k) hru=$((hru - 1)) ;;
    h) hru=$((hru + 1)) ;;
    g) git=1 ;;
    s) eza_opts+=(-S) ;;
    X) eza_opts+=(-s extension) ;;
    # Both take a value; without one eza rejects the flag outright.
    I | L) eza_opts+=(-"$arg" "$OPTARG") ;;
    1 | l | F | R | d | i | T | x) eza_opts+=(-"$arg") ;;
    # '?' is a flag with no mapping, and ':' a mapped one missing its value.
    *) fallback "-$OPTARG" ;;
  esac
done

# GNU ls accepts options after a path (`ls dir -la`); getopts stops at the first
# path, and eza would read what follows with its own meanings, not ls's. A `--`
# makes everything after it a path, so only check when there wasn't one.
if ((OPTIND == 1)) || [[ ${original[OPTIND - 2]} != -- ]]; then
  for argument in "${original[@]:OPTIND-1}"; do
    [[ $argument == -?* ]] && system_ls "${original[@]}"
  done
fi

shift "$((OPTIND - 1))"

((rev % 2 == 1)) && eza_opts+=(-r)
((hru <= 0)) && eza_opts+=(-B)
((fgp == 0)) && eza_opts+=(-g)
((lnk == 0)) && eza_opts+=(-H)

# git -C wants a directory, and the first path may be a file or absent.
directory="${1:-.}"
if [[ ! -d $directory ]]; then
  if [[ $directory == */* ]]; then
    directory="${directory%/*}"
    directory="${directory:-/}"
  else
    directory=.
  fi
fi

if [[ $(git -C "$directory" rev-parse --is-inside-work-tree 2>/dev/null) == true ]]; then
  git=1
fi

# Added once: eza rejects --git given twice, which -g in a repository did.
((git == 1)) && eza_opts+=(--git)

# --color-scale and --icons each take an *optional* value, and clap would read
# the next token as that value unless it starts with a dash; attaching the
# values keeps a bare `ls` from losing its first path. `--` keeps a path that
# starts with a dash from being read as an option.
exec eza --color-scale=all --color=always --icons=auto "${eza_opts[@]}" -- "$@"
