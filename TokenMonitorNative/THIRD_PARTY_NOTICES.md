# Third-party notices and provenance

## Token Monitor

This independently maintained native Swift application is inspired by [Javis603/token-monitor](https://github.com/Javis603/token-monitor) and interoperates with its v0.56.0 Hub API baseline. It is not an official upstream or OpenAI client.

Versions 0.5–0.6 reused MIT-licensed backend modules from upstream commit `2f60827e3028d283969dd74cde5b3f5664220442`. Version 0.7 replaces the bundled Node collector with Swift and removes the obsolete vendored runtime from the current tree. Historical source and its patches remain in the corresponding Git tags. The [upstream MIT license](Resources/TOKEN-MONITOR-LICENSE) is retained for provenance and any derived protocol/implementation work; no claim is made that all project code was created without reference to upstream work.

## Distributed dependencies and assets

- **Sparkle 2.10.0** — [Sparkle](https://github.com/sparkle-project/Sparkle), MIT. Pinned in Package.swift and Package.resolved. The full license is included in the app at `Contents/Resources/Licenses/Sparkle.txt`.
- **Apple frameworks** — SwiftUI, AppKit, Foundation, Network, Security and other platform frameworks are provided by macOS.
- **ReferenceGear** — unmodified gear symbol exported from Apple SF Symbols 7.2, subject to Apple's SF Symbols license. It is not covered by the upstream MIT license.
- **Device icons** — Icons by [Icons8](https://icons8.com), subject to the Icons8 license. [Asset credits](Resources/DEVICE-ICON-CREDITS.md) are included in the app and linked from About.

Node.js, Tokscale, Electron, and npm dependencies are not included in 0.7.0. Their historical distributions retain their own licenses in the corresponding releases and tags.

No unified open-source license has yet been assigned to this repository's new code. The licenses above apply to their respective components.
