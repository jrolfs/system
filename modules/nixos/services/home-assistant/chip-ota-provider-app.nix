{ lib, stdenv, fetchurl, autoPatchelfHook, libnl }:

# The OTA provider the Matter server starts for each firmware update it hands
# a device. The server's Docker image downloads this prebuilt binary into
# /usr/local/bin and nixpkgs doesn't package it, so without it every update
# offered in Home Assistant fails with "No such file or directory:
# 'chip-ota-provider-app'". The release is the one python-matter-server's
# Dockerfile names for the server version nixpkgs ships; bump them together.

stdenv.mkDerivation (finalAttrs: {
  pname = "chip-ota-provider-app";
  version = "2025.9.0";

  src = fetchurl {
    url = "https://github.com/home-assistant-libs/matter-linux-ota-provider/releases/download/${finalAttrs.version}/chip-ota-provider-app-x86-64";
    hash = "sha256-RVDfevZSnkYgRj0cASf4MOwkBMgXrUxjQ7KeMs7AFE4=";
  };

  dontUnpack = true;

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    libnl
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/chip-ota-provider-app
    runHook postInstall
  '';

  meta = {
    description = "Matter OTA provider used by python-matter-server for device firmware updates";
    homepage = "https://github.com/home-assistant-libs/matter-linux-ota-provider";
    license = lib.licenses.asl20;
    mainProgram = "chip-ota-provider-app";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
