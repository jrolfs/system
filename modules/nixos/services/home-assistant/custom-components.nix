{ buildHomeAssistantComponent, fetchFromGitHub, fetchPypi, home-assistant }:

# The custom integrations Leia's Home Assistant runs that nixpkgs doesn't
# package, at the versions installed there when this was written. HACS
# installed them on Leia; here they are pinned like anything else, and the
# NixOS module links them into custom_components.

let
  inherit (home-assistant) python3Packages;

  hatch-rest-api = python3Packages.buildPythonPackage rec {
    pname = "hatch_rest_api";
    version = "1.34.5";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-QhaMrdHDBlS2V0i+Oh9PsUD1XJu+UHxmmvCzvxCn4J4=";
    };

    build-system = [ python3Packages.setuptools ];

    dependencies = with python3Packages; [ aiohttp awsiotsdk ];

    pythonImportsCheck = [ "hatch_rest_api" ];
  };
in
{
  inherit hatch-rest-api;

  # Vendors its own copy of libdyson, so it has no requirements beyond the
  # mqtt and zeroconf components it declares as dependencies.
  dyson-local = buildHomeAssistantComponent rec {
    owner = "libdyson-wg";
    domain = "dyson_local";
    version = "1.5.7";

    src = fetchFromGitHub {
      owner = "libdyson-wg";
      repo = "ha-dyson";
      tag = "v${version}";
      hash = "sha256-V5RCepikTDrjZwi6MfRislpV2F9jR1MqwWxTq0GPBp4=";
    };
  };

  ha-hatch = buildHomeAssistantComponent rec {
    owner = "dahlb";
    domain = "ha_hatch";
    version = "1.31.9";

    src = fetchFromGitHub {
      owner = "dahlb";
      repo = "ha_hatch";
      tag = "v${version}";
      hash = "sha256-3GZbDQxextiBxfsUXU16P/cuS7lh3pzcmXYxF/ojOFs=";
    };

    dependencies = [ hatch-rest-api ];
  };
}
