"""Configure Meta DAT in an unsigned OpenVision IPA before signing it."""
import argparse
import getpass
import plistlib
import re
import shutil
import sys
from pathlib import Path
from zipfile import ZipFile

INFO = "Payload/OpenVision.app/Info.plist"


def configure(source, output, app_id, token, team, bundle):
    if not re.fullmatch(r"[0-9]+", app_id) or int(app_id) == 0:
        raise ValueError("El Meta App ID debe ser un número distinto de cero.")
    if not re.fullmatch(rf"AR\|{app_id}\|[^|\s]+", token):
        raise ValueError("El Client Token debe tener el formato AR|APP_ID|TOKEN y coincidir con el App ID.")
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError("El Apple Team ID debe tener 10 caracteres.")
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", bundle):
        raise ValueError("El identificador de app debe tener un formato como com.ejemplo.openvision.")

    with ZipFile(source) as original:
        if any(name.startswith("Payload/OpenVision.app/_CodeSignature/") for name in original.namelist()):
            raise ValueError("Selecciona la IPA sin firmar de GitHub Actions.")
        raw = original.read(INFO)
        info = plistlib.loads(raw)
        if not isinstance(info.get("MWDAT"), dict):
            raise ValueError("La IPA no contiene la configuración MWDAT de OpenVision.")
        info["MWDAT"].update(MetaAppID=app_id, ClientToken=token, TeamID=team)
        previous_bundle = info["CFBundleIdentifier"]
        info["CFBundleIdentifier"] = bundle
        for url_type in info.get("CFBundleURLTypes", []):
            if url_type.get("CFBundleURLName") == previous_bundle:
                url_type["CFBundleURLName"] = bundle
        fmt = plistlib.FMT_BINARY if raw.startswith(b"bplist00") else plistlib.FMT_XML
        replacement = plistlib.dumps(info, fmt=fmt, sort_keys=False)
        with output.open("xb") as target:
            try:
                with ZipFile(target, "w") as updated:
                    for entry in original.infolist():
                        if entry.filename == INFO:
                            updated.writestr(entry, replacement)
                        else:
                            with original.open(entry) as reader, updated.open(entry, "w") as writer:
                                shutil.copyfileobj(reader, writer)
            except BaseException:
                target.close()
                output.unlink()
                raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path, help="Ruta de OpenVision-unsigned.ipa")
    args = parser.parse_args()
    output = args.ipa.with_name("OpenVision-meta-unsigned.ipa")
    try:
        with ZipFile(args.ipa) as ipa:
            default_bundle = plistlib.loads(ipa.read(INFO))["CFBundleIdentifier"]
        bundle = input(f"Identificador de app usado en Meta y Sideloadly [{default_bundle}]: ").strip()
        team = input("Apple Team ID: ").strip().upper()
        app_id = input("Meta App ID: ").strip()
        token = getpass.getpass("Client Token de Meta (oculto): ").strip()
        configure(args.ipa, output, app_id, token, team, bundle or default_bundle)
    except (OSError, ValueError, KeyError) as error:
        sys.exit(f"Error: {error}")
    print(f"IPA sin firmar creada: {output}")


if __name__ == "__main__":
    main()
