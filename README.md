# Serafin

[![CI](https://github.com/timsullivan2019/serafin/actions/workflows/ci.yml/badge.svg)](https://github.com/timsullivan2019/serafin/actions/workflows/ci.yml)

Serafin is a native SwiftUI client for Jellyfin on iPhone and iPad, built around Liquid Glass so your own movies and shows look and feel like they belong in an Apple app. It talks only to your server, keeps your access token in the Keychain, and collects nothing about you. Serafin is an independent project and is not affiliated with or endorsed by the Jellyfin project.

## Building

Serafin needs Xcode 26 or later (iOS 26.1 is the minimum OS) and [XcodeGen](https://github.com/yonaskolb/XcodeGen), which generates the Xcode project from `project.yml`.

```sh
brew install xcodegen
xcodegen generate
open Serafin.xcodeproj
```

From the command line:

```sh
xcodebuild -scheme Serafin -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme Serafin -destination 'platform=iOS Simulator,name=iPhone 17' test
swift test --package-path Packages/SerafinKit
```

Contributors should read [AGENTS.md](AGENTS.md) for the architecture, conventions and security rules, and [docs/PLAN.md](docs/PLAN.md) for the work plan.

## Licence

The code is released under the [MIT licence](LICENSE). The Serafin name and icon are not covered by it; see [TRADEMARK.md](TRADEMARK.md).
