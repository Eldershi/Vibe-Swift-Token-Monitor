# Vendored backend

Source: https://github.com/Javis603/token-monitor
Commit: `2f60827e3028d283969dd74cde5b3f5664220442` (0.56.0).
Included: shared modules, Hub and headless runtime; MIT license in vendor/LICENSE.
Native beta patches: read-only credential mode disables refresh, CLI/RPC fallback and reset-credit queries; Hub request interception provides beta controls. Read-only Claude Keychain reads use the injected native noninteractive helper; no security CLI fallback. Other providers are not enabled.
Tokscale fork and checksum: tokscale-pin.json. Production dependencies are pinned by package-lock.json; no Electron dependency is shipped.

Distribution patch: unused embedded Antigravity OAuth secret and Claude OAuth client ID are omitted; native collection does not enable Antigravity or credential refresh. Claude refresh fails closed; valid read-only quota queries remain available.
