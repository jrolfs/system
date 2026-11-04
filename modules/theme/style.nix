# The shell's look as plain data, beside palette.nix and fonts.nix and read the
# same way: corner radii, the glass and its rim, the ink and fill alphas,
# spacing, type size and motion. The desktop shell declares these into its
# settings (modules/home/linux/desktop/shell), and the emulator station's
# Pegasus theme bakes them in at build time (modules/nixos/arcade/theme), so
# both draw the same surfaces and a change here moves both.
#
# Names are the shell's own settings keys, so they carry over without a
# mapping. Sizes are logical pixels on a 1920×1080 canvas, which is what the
# shell sees on Irulan's TV at scale 2. Alphas and opacities are percentages,
# durations milliseconds.

{
  # Corners. Medium matches Hyprland's window rounding (look.nix).
  radiusSmall = 10;
  radiusMedium = 14;
  radiusLarge = 22;
  islandRadius = 22;
  islandRadiusOpen = 32;

  # Glass: a translucent pane over a blurred backdrop, edged with a faint light
  # rim. The stronger pane is for one stacked on another.
  glassOpacity = 72;
  glassStrongOpacity = 86;
  rimAlpha = 12;
  selectionAlpha = 8;
  surfaceTint = 5;

  # Ink and fills, as alphas of the palette's foreground.
  hairlineAlpha = 14;
  inkDimAlpha = 60;
  inkFaintAlpha = 35;
  fillLowAlpha = 6;
  fillHighAlpha = 13;
  scrimOpacity = 50;

  # One soft shadow under a floating surface, kept faint because the pane is
  # translucent and a strong one shows through it as mud.
  shadowOpacity = 14;
  shadowBlur = 100;
  shadowOffsetY = 10;
  shadowSpread = 80;

  spacingUnit = 4;
  fontSize = 14;
  iconSize = 18;
  # Tenths of a pixel, in the icons' 24-unit box.
  iconStroke = 22;
  launcherRowHeight = 44;

  # Springs for position and size, a critically damped curve for fades.
  # Bounce runs from 0 (none) to 100 (as springy as the curve goes).
  motionSpring = 400;
  motionEffects = 230;
  motionFast = 140;
  motionBounce = 56;
}
