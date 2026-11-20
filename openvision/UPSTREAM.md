# Upstream attribution

This test branch incorporates the OpenVision iOS sources, tests, configuration templates and vendored build dependencies from [rayl15/OpenVision](https://github.com/rayl15/OpenVision/tree/b1e2350d0b37b7ca273f6e3c505dec254bd78370), commit `b1e2350d0b37b7ca273f6e3c505dec254bd78370`.

Copyright (c) 2026 OpenVision Contributors. See [LICENSE](LICENSE) and the original licenses inside `Vendor/`. SwiftPM retrieves the Meta SDK and other remote packages during build.

Local changes provide development-mode defaults without credentials, add Meta camera network configuration, and build for arm64 iOS devices and simulators in GitHub Actions.
