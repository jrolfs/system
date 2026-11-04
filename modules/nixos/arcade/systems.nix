# The consoles the station plays, and the one place each is described.
# Everything per-system derives from this list: the ROM directories, the
# Pegasus collection headers, the RetroArch core each launches with, and the
# Skyscraper platforms arcade-scrape works through.
#
# Attribute names are Skyscraper's platform ids, so the scraper, the directory
# under roms/ and the collection's shortname all agree without a mapping table.
# `name` is the collection's full name, `label` the shorter one on the game
# menu's system tabs, and `core` names a package in pkgs.libretro.
#
# Cores, where there was a choice:
#   megadrive and friends  genesis-plus-gx: the accurate Sega core, and the one
#                          that also covers Master System, Game Gear and Sega CD
#   nes                    mesen: the most accurate NES core
#   n64                    mupen64plus (mupen64plus-next): far better game
#                          compatibility and maintenance than parallel-n64
#   psx                    swanstation: DuckStation's libretro port, accurate
#                          with a hardware renderer and light enough to upscale
#                          on an iGPU, where beetle-psx-hw is heavier for the
#                          same games
#   gb, gbc, gba           mgba: one core for all three
#
# Extensions leave out .bin for psx and segacd: there it's the data track a
# .cue points at, and listing it would show every disc twice.

{
  megadrive = {
    name = "Sega Genesis";
    label = "Genesis";
    core = "genesis-plus-gx";
    extensions = [ "md" "gen" "smd" "bin" "zip" "7z" ];
  };

  mastersystem = {
    name = "Sega Master System";
    label = "Master System";
    core = "genesis-plus-gx";
    extensions = [ "sms" "zip" "7z" ];
  };

  gamegear = {
    name = "Sega Game Gear";
    label = "Game Gear";
    core = "genesis-plus-gx";
    extensions = [ "gg" "zip" "7z" ];
  };

  segacd = {
    name = "Sega CD";
    label = "Sega CD";
    core = "genesis-plus-gx";
    extensions = [ "chd" "cue" "iso" "m3u" ];
  };

  nes = {
    name = "Nintendo Entertainment System";
    label = "NES";
    core = "mesen";
    extensions = [ "nes" "fds" "zip" "7z" ];
  };

  snes = {
    name = "Super Nintendo";
    label = "SNES";
    core = "snes9x";
    extensions = [ "sfc" "smc" "zip" "7z" ];
  };

  n64 = {
    name = "Nintendo 64";
    label = "N64";
    core = "mupen64plus";
    extensions = [ "n64" "z64" "v64" "zip" "7z" ];
  };

  gb = {
    name = "Game Boy";
    label = "Game Boy";
    core = "mgba";
    extensions = [ "gb" "zip" ];
  };

  gbc = {
    name = "Game Boy Color";
    label = "Game Boy Color";
    core = "mgba";
    extensions = [ "gbc" "zip" ];
  };

  gba = {
    name = "Game Boy Advance";
    label = "GBA";
    core = "mgba";
    extensions = [ "gba" "zip" ];
  };

  psx = {
    name = "PlayStation";
    label = "PlayStation";
    core = "swanstation";
    extensions = [ "chd" "cue" "pbp" "m3u" ];
  };
}
