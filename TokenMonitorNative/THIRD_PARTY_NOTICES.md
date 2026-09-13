# Third-party notices and project relationship

Token Monitor: https://github.com/Javis603/token-monitor (MIT license).
This is an independently maintained native macOS derivative, not an official client endorsed by the upstream author and not a GitHub fork. It interoperates with the v0.56.0 Hub API. The 0.4.1 client did not bundle Electron or collectors. Version 0.5 bundles a pinned MIT-licensed subset of the upstream shared collectors, account quota readers and Hub; it does not bundle Electron or its branding assets. See Backend/UPSTREAM.md and Backend/vendor/LICENSE. Synthetic fixtures are generated locally from the documented field shapes.

SwiftUI, AppKit, Foundation, Security and Swift Charts are Apple system frameworks. Sparkle is referenced as a future integration and is not bundled or enabled.

Version 0.5 bundles Node.js 24.19.0 (MIT and incorporated dependency notices, included as Backend/runtime/NODE-LICENSE in the app), Tokscale 4.15.1 with the pinned downstream fork (MIT), and the production npm dependencies identified in Backend/package-lock.json. Their package license files are included in the app. Source and download pins are documented in Backend/UPSTREAM.md, runtime-pin.json and tokscale-pin.json.

ReferenceGear is the unmodified gear symbol exported from Apple SF Symbols 7.2 (font version 21.1d1e1). It is included as an Apple symbol asset for this macOS app, subject to Apple’s SF Symbols license; it is not an original project icon or covered by the upstream MIT license.
