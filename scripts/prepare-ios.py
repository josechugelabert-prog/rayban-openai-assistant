#!/usr/bin/env python3
"""Generate the iOS project from a pinned, official Meta CameraAccess sample."""
import os
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / ".build"
OUTPUT = BUILD / "rayban-ios"
REF = "41d79001da0dde6ab3eaccc5e2e60ff850241b60"
REMOTE = "https://github.com/facebook/meta-wearables-dat-ios.git"


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"Expected exactly one upstream match for {old!r}")
    return text.replace(old, new, 1)


def main():
    BUILD.mkdir(exist_ok=True)
    seed = os.environ.get("META_SDK_CHECKOUT")
    with tempfile.TemporaryDirectory(dir=BUILD) as tmp:
        staging = Path(tmp)
        sdk = Path(seed).resolve() if seed else staging / "sdk"
        if not seed:
            git("init", "--quiet", str(sdk))
            git("-C", str(sdk), "fetch", "--depth=1", REMOTE, REF)
            git("-C", str(sdk), "checkout", "--detach", "FETCH_HEAD")
        if git("-C", str(sdk), "rev-parse", "HEAD") != REF:
            raise ValueError("Meta SDK checkout does not match the pinned commit")
        if git("-C", str(sdk), "status", "--porcelain", "--untracked-files=all"):
            raise ValueError("Meta SDK checkout has local changes")
        project = staging / "rayban-ios"
        shutil.copytree(sdk / "samples/CameraAccess", project)
        for name in ("LICENSE", "NOTICE"):
            shutil.copy2(sdk / name, project)
        app = project / "CameraAccess"

        plist = app / "Info.plist"
        info = plistlib.loads(plist.read_bytes())
        info["CFBundleDisplayName"] = "RayBan OpenAI Assistant"
        info["CFBundleURLTypes"][0]["CFBundleURLSchemes"] = ["raybanopenaiassistant"]
        info["MWDAT"]["AppLinkURLScheme"] = "raybanopenaiassistant://"
        info["NSMicrophoneUsageDescription"] = (
            "Graba tu consulta cuando pulsas Grabar. El audio se envía al pulsar Enviar."
        )
        plist.write_bytes(plistlib.dumps(info, sort_keys=False))

        pbx = project / "CameraAccess.xcodeproj/project.pbxproj"
        original = pbx.read_text()
        if original.count("com.meta.wearables.external.CameraAccess") < 2:
            raise ValueError("Unexpected upstream bundle identifiers")
        code = original.replace("com.meta.wearables.external.CameraAccess",
                                "com.raybanassistant.CameraAccess")
        upstream_ref = "8FD96B792E6F0A9800F56AB1"
        upstream_build = "8FD96B7F2E6F0A9800F56AB1"
        assistant_ref = "F014AB000000000000000001"
        assistant_build = "F014AB000000000000000002"
        lines = []
        added = 0
        for line in code.splitlines(keepends=True):
            lines.append(line)
            if "CameraAccessApp.swift" in line:
                lines.append(line.replace("CameraAccessApp.swift", "AssistantView.swift")
                             .replace(upstream_ref, assistant_ref)
                             .replace(upstream_build, assistant_build))
                added += 1
        if added != 4:
            raise ValueError("Unexpected upstream app source references")
        pbx.write_text("".join(lines))
        shutil.copy2(ROOT / "ios/AssistantView.swift", app)

        entry = app / "CameraAccessApp.swift"
        code = replace_once(
            entry.read_text(),
            "MainAppView(wearables: Wearables.shared, viewModel: wearablesViewModel)",
            """TabView {
        MainAppView(wearables: Wearables.shared, viewModel: wearablesViewModel)
          .tabItem { Label("Gafas", systemImage: "eyeglasses") }
        AssistantView()
          .tabItem { Label("Asistente", systemImage: "waveform") }
      }""",
        )
        entry.write_text(code)
        preview = app / "Views/CapturePreviewView.swift"
        code = replace_once(preview.read_text(), "@State private var showShareSheet = false",
                            "@State private var showShareSheet = false\n  @State private var showAssistant = false")
        code = replace_once(code, ".accessibilityIdentifier(\"share_button\")",
                            """.accessibilityIdentifier("share_button")
        if case .photo = preview {
          Button("Analizar foto") { showAssistant = true }
            .buttonStyle(.borderedProminent)
        }""")
        code = replace_once(code, ".onAppear { player?.play() }", """.onAppear { player?.play() }
    .fullScreenCover(isPresented: $showAssistant) {
      if case .photo(let image) = preview {
        NavigationStack {
          AssistantView(image: image)
            .toolbar {
              Button("Cerrar") { showAssistant = false }
            }
        }
      }
    }""")
        preview.write_text(code)

        if OUTPUT.exists():
            shutil.rmtree(OUTPUT)
        project.rename(OUTPUT)
    print(OUTPUT / "CameraAccess.xcodeproj")


if __name__ == "__main__":
    main()
