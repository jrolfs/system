{ ... }:

# Host keys, so the first connection to any of these never stops at a
# fingerprint prompt, which nothing non-interactive (a fetch from activation,
# an rsync from a script) can answer.
#
# The machines' own keys are the ones each generated at install, as already
# recorded in known_hosts from connecting by hand. Reinstalling a machine
# replaces its key, and this is the entry to update when it does
# (`cat /etc/ssh/ssh_host_ed25519_key.pub` on that machine). Which identity
# connects is settled elsewhere: modules/home/shared/ssh.nix derives every
# machine's authorized_keys from the one GPG key.

let
  machine = name: publicKey: {
    hostNames = [ name "${name}.rolfs.lan" ];
    inherit publicKey;
  };
in
{
  programs.ssh.knownHosts = {
    "github.com/rsa" = {
      hostNames = [ "github.com" ];
      publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=";
    };
    "github.com/ecdsa" = {
      hostNames = [ "github.com" ];
      publicKey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=";
    };
    "github.com/ed25519" = {
      hostNames = [ "github.com" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
    };

    ala = machine "ala" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIITGKjp3GNsD8N8h/LyKrOfsv4NOuZVClnoez98raV95";
    adrian = machine "adrian" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGOfDn8FW2kQZq/s9PyvRNssilCjWxcZVxJwNlVf/e+Z";
    irulan = machine "irulan" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICelOBZdNT0CZzV9zDcr1uQg5BKw/qmOQPOigP7iqQY1";
  };
}
