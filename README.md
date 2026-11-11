# MiBudMac

SwiftUI companion for Redmi Buds 6 Play on macOS 14 or later.

## Features

* Battery levels for each earbud and the case, with charging indicators.
* Five equalizer presets: Standard, Treble, Bass, Voice, and Volume.
* Low latency control.
* Separate gesture assignments for each earbud.
* Menu bar controls and automatic reconnection.

Settings are read back from the earbuds after each change. Unavailable battery levels display as N/A.

## Build

Install Xcode, then run:

```sh
swift test
bash scripts/build.sh
open dist/MiBuds.app
```

Open `Package.swift` in Xcode to edit the project. No external packages are required. The build signs the app locally; it is not notarized.

## Connect

Pair Redmi Buds 6 Play in macOS Bluetooth Settings, then open MiBuds. Allow Bluetooth access when prompted. The app connects automatically.

If controls do not respond, close other earbud companion apps and reconnect. Connection diagnostics are available in the Connection panel and at `~/Library/Logs/MiBuds/connection.log`.

Closing the window leaves the menu bar companion running. Use Quit MiBuds to exit.

## Development

`Sources/MiBudsCore` contains packet framing, settings codecs, and authentication. `Sources/MiBudsMac` contains the native Bluetooth transport and interface. `Tests/MiBudsCoreTests` covers framing, settings validation, and authentication.

Format Swift source with:

```sh
swift format format --in-place --recursive Sources Tests scripts Package.swift
```

## Compatibility

The app has received battery levels, equalizer state, latency state, and gesture assignments from Redmi Buds 6 Play on macOS. Hardware writes have not yet been verified. Case battery is only shown when reported by the earbuds. Other models, custom equalizer bands, noise cancellation, and firmware updates are not supported.

## License and credits

The complete application uses [GPLv3](LICENSE). Original interface files are also available under [MIT](LICENSES/MIT.txt). See [Credits](CREDITS.md) for file scope and attribution to MiBudsClient, LeandroPG19/Buds, and the protocol research they reference.
