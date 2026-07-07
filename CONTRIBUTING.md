# Contributing

Thanks for helping improve HermesShare.

## Development setup

1. Fork and clone the repo.
2. `brew install xcodegen`
3. `xcodegen generate && open HermesShare.xcodeproj`
4. Set your `DEVELOPMENT_TEAM` in `project.yml` or Xcode signing settings.
5. Run tests: `xcodebuild -scheme HermesShare -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`

## Pull requests

- Keep changes focused — schema, renderer, extension, or docs in separate PRs when possible.
- Add or update unit tests for schema and routing changes.
- If you add a new `HermesNode` case, update `docs/LAYOUT.md` and add a sample fixture.
- Verify on Simulator (debug harness + Messages extension) before submitting.

## Schema changes

New node types require updates in four places:

1. `Shared/Sources/HermesShared/HermesLayout.swift` — enum case + associated values
2. `HermesLayoutCodable.swift` — wire format discriminator
3. `HermesLayoutRenderer.swift` — SwiftUI view
4. `docs/LAYOUT.md` — authoring documentation

## Reporting bugs

Include: iOS version, build stamp from the extension empty state (if visible), steps to reproduce,
and whether the card arrived via Photon or local compose.
