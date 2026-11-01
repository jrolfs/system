{ pkgs, lib, ... }:

# Smallstep CA — internal LAN certificate authority. Migrated from a
# Docker container on QNAP (smallstep/step-ca:latest) where the data
# lived in a named docker volume step-ca-data mounted at /home/step.
#
# Migration: stop the step-ca container on QNAP. Tar up the volume
# contents (`docker run --rm -v step-ca-data:/data busybox tar czf - /data
# > step-ca.tar.gz`), copy to Irulan, extract into /var/lib/step-ca.
# Adjust ownership to the step-ca user (services.step-ca creates it).
#
# The intermediate password file at /var/lib/step-ca/secrets/password
# must be readable by the step-ca user but not world-readable. Set it
# up out of band before first start, reading the password on a machine
# with desktop-app 1Password rather than here: a short-form reference
# resolves against the Private vault, and a host authenticating with a
# service account cannot read Private at all. Either copy it across, or
# give this a sops-nix secret the way komodo.nix plans to.

{
  services.step-ca = {
    enable = true;
    address = "0.0.0.0";
    port = 443;

    # TODO(migration): path to the migrated intermediate key password.
    # Set up manually before the first nixos-rebuild switch on Irulan.
    intermediatePasswordFile = "/var/lib/step-ca/secrets/password";

    # settings get merged into ca.json. Most options can stay default —
    # the migrated /var/lib/step-ca/config/ca.json brings the existing
    # CA's roots, intermediate, and provisioners. The settings block
    # below is for any overlays the NixOS module needs to know about.
    settings = {
      # Pre-existing CA configuration loads from the migrated config dir.
      # Leave settings empty for v1; refine if step-ca complains about
      # missing keys.
    };
  };

  # Port 443 conflicts with traefik. Two ways to resolve:
  #  (a) step-ca listens on a non-standard port (e.g. 8443) and traefik
  #      proxies https://step-ca.rolfs.lan to it
  #  (b) step-ca listens on a separate LAN IP via macvlan (matches the
  #      QNAP setup where step-ca had its own container with its own port)
  # TODO(networking): pick one before deploying. (a) is simpler.
}
