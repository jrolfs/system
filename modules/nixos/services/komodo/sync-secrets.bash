# Upserts Komodo secret variables from 1Password, one per entry in $MANIFEST
# ({"NAME": "op://…"}). Every value is read before anything is written, so a
# failed read leaves Komodo exactly as it was. Values only ever pass through
# files in the private runtime directory and stdin: never argv, never the log.

work="${RUNTIME_DIRECTORY:?}"

# The rendered header file holds the API key and secret, so they reach curl
# as `-H @file` rather than on its command line.
call() {
  curl --fail --silent --show-error --max-time 15 \
    --header @"$HEADERS" --header 'content-type: application/json' \
    --data-binary @- "$CORE/$1"
}

OP_SERVICE_ACCOUNT_TOKEN="$(< "$TOKEN_FILE")"
export OP_SERVICE_ACCOUNT_TOKEN

mapfile -t names < <(jq -r 'keys[]' "$MANIFEST")

for name in "${names[@]}"; do
  reference="$(jq -r --arg name "$name" '.[$name]' "$MANIFEST")"
  if ! op read --no-newline "$reference" > "$work/$name" 2> "$work/op.err"; then
    echo "$name: 1Password couldn't read $reference ($(tr -d '\n' < "$work/op.err")); nothing was changed in Komodo" >&2
    exit 1
  fi
  # A blank variable would deploy stacks with an empty secret.
  if [ ! -s "$work/$name" ]; then
    echo "$name: $reference is empty in 1Password; nothing was changed in Komodo" >&2
    exit 1
  fi
done

# Core can still be starting when this runs at boot.
for attempt in $(seq 30); do
  if echo '{}' | call read/ListVariables > "$work/existing.json" 2> /dev/null; then
    break
  fi
  if [ "$attempt" = 30 ]; then
    echo "Komodo Core at $CORE didn't answer; nothing was changed" >&2
    exit 1
  fi
  sleep 5
done

for name in "${names[@]}"; do
  reference="$(jq -r --arg name "$name" '.[$name]' "$MANIFEST")"
  description="Managed from 1Password ($reference) by komodo-secrets-sync on $HOST; edits here are overwritten."

  # The comparison happens inside jq, so only its verdict is ever printed.
  state="$(jq -r --arg name "$name" --rawfile value "$work/$name" --arg description "$description" '
    (map(select(.name == $name)) | first) as $existing
    | if $existing == null then "missing"
      else [
        (if $existing.value != $value then "value" else empty end),
        (if $existing.is_secret != true then "secret" else empty end),
        (if $existing.description != $description then "description" else empty end)
      ] | join(" ") end
  ' "$work/existing.json")"

  case "$state" in
    missing)
      jq -n --arg name "$name" --rawfile value "$work/$name" --arg description "$description" \
        '{name: $name, value: $value, description: $description, is_secret: true}' \
        | call write/CreateVariable > /dev/null
      echo "$name: created"
      ;;
    "")
      echo "$name: unchanged"
      ;;
    *)
      if [[ $state == *value* ]]; then
        jq -n --arg name "$name" --rawfile value "$work/$name" '{name: $name, value: $value}' \
          | call write/UpdateVariableValue > /dev/null
      fi
      if [[ $state == *secret* ]]; then
        jq -n --arg name "$name" '{name: $name, is_secret: true}' \
          | call write/UpdateVariableIsSecret > /dev/null
      fi
      if [[ $state == *description* ]]; then
        jq -n --arg name "$name" --arg description "$description" '{name: $name, description: $description}' \
          | call write/UpdateVariableDescription > /dev/null
      fi
      echo "$name: updated ($state)"
      ;;
  esac
done

# Undeclared secret variables are left alone, since something else may own
# them, but listed so a forgotten one is visible.
jq -r --slurpfile manifest "$MANIFEST" '
  map(select(.is_secret and (.name as $n | $manifest[0] | has($n) | not)) | .name)
  | if length > 0 then "secret variables not managed here: \(join(", "))" else empty end
' "$work/existing.json"
