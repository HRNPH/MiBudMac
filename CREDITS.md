# Credits

## MiBudsClient

[CesurPolat/MiBudsClient](https://github.com/CesurPolat/MiBudsClient) is the source for the Bluetooth protocol adaptation, authentication exchanges, device settings, gesture options, and earbud image. This project translates that implementation into Swift.

Source revision: [`9601abb2fd604099b75144cbec4d74eb736ebb51`](https://github.com/CesurPolat/MiBudsClient/tree/9601abb2fd604099b75144cbec4d74eb736ebb51).

The adapted files retain GPLv3 licensing:

* `Sources/MiBudsCore/Protocol.swift`
* `Sources/MiBudsCore/Authentication.swift`
* `Sources/MiBudsCore/SaferPlus.swift`
* `Sources/MiBudsMac/BudsController.swift`
* `Tests/MiBudsCoreTests/ProtocolTests.swift`
* `Sources/MiBudsMac/Resources/earbuds.png`

The image comes from [`assets/images/MiBuds6Play.png`](https://github.com/CesurPolat/MiBudsClient/blob/9601abb2fd604099b75144cbec4d74eb736ebb51/assets/images/MiBuds6Play.png). The tests retain the authentication vectors published in [`tests/test_command_auth.py`](https://github.com/CesurPolat/MiBudsClient/blob/9601abb2fd604099b75144cbec4d74eb736ebb51/tests/test_command_auth.py).

## Authentication algorithm

The SAFER+ variant in MiBudsClient was taken from [LeandroPG19/Buds](https://github.com/LeandroPG19/Buds/blob/e7e25b084114932ca962a61b35a37e5237702154/bluetooth/safer_plus.py), revision `e7e25b084114932ca962a61b35a37e5237702154`, under GPLv3. `Sources/MiBudsCore/SaferPlus.swift` is a translation of that algorithm.

The [upstream module](https://github.com/CesurPolat/MiBudsClient/blob/9601abb2fd604099b75144cbec4d74eb736ebb51/controllers/bluetooth/safer_plus.py) also credits Gadgetbridge protocol research and XiaomayEarbudsWin. Those acknowledgments are retained here. This repository does not claim to have performed the hardware tests described by those projects.

## Original interface

Copyright 2026 HRNPH. These original files are available under the [MIT License](LICENSES/MIT.txt):

* `Sources/MiBudsMac/ContentView.swift`
* `Sources/MiBudsMac/MiBudsApp.swift`
* `scripts/makeIcon.swift`

The combined application remains under [GPLv3](LICENSE). The MIT grant covers the original interface files, not the adapted Bluetooth implementation or earbud image.

## Platform

The application uses Apple's SwiftUI, AppKit, IOBluetooth, and system symbols. The application icon is drawn from the system earbuds symbol by `scripts/makeIcon.swift`.

Xiaomi and Redmi are trademarks of their respective owners. MiBudMac is not affiliated with Xiaomi.
