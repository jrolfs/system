# The desktop's shape, shared by hyprland.nix and the shell. Plain data, read
# the way palette.nix and fonts.nix are.
#
# One source because the two have to agree: the shell's island reserves its
# exclusive zone from gapsOut, and Game Mode zeroes Hyprland's gaps and
# rounding and later restores them from the values the shell was given. A
# shell told 12 while Hyprland uses 15 leaves windows overlapping the island.

{
  gapsIn = 6;
  gapsOut = 12;
  border = 2;

  # Matches the shell's medium radius and its screen corners, so a window's
  # corners and the shell's glass cards curve alike. Hyprland's old 10 read as
  # nearly square beside them.
  rounding = 14;

  blurSize = 8;
  blurPasses = 3;
}
