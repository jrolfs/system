export LC_ALL=C
umask 077

password=$(< "$CREDENTIALS_DIRECTORY/password")
if [[ ! $password =~ ^[a-zA-Z0-9]{8}$ ]]; then
  echo "VNC requires a dedicated password of exactly eight ASCII letters or digits." >&2
  exit 1
fi

# macOS Screen Sharing needs legacy VNC authentication. These two flags allow
# it without allowing unauthenticated clients. Traffic is not encrypted, so
# the host firewall and router's VPN are the transport security boundary.
{
  printf '%s\n' \
    'address=0.0.0.0' \
    'port=5900' \
    'enable_auth=true' \
    'relax_encryption=true' \
    'allow_broken_crypto=true'
  printf 'password=%s\n' "$password"
} > "$RUNTIME_DIRECTORY/config"
unset password

# A viewer window's size must not change the TV's display mode.
exec wayvnc --config="$RUNTIME_DIRECTORY/config" --output="$1" --disable-resizing
