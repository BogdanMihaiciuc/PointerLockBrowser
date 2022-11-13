#  1. Introduction

PointerLockBrowser is an iOS app whose purpose is to make it possible to play mouse and keyboard games on iPad via Geforce Now. It includes a single screen with a `WKWebView` that loads a hardcoded URL (set to Geforce Now).

To make mouse and keyboard games playable it includes a shim for the [pointer lock API](https://developer.mozilla.org/en-US/docs/Web/API/Pointer_Lock_API) which is unsupported in mobile safari, despite being supported in the desktop version and UIKit apps. The shim makes use of the native `UIViewController` [`prefersPointerLocked`](https://developer.apple.com/documentation/uikit/uiviewcontroller/3601235-preferspointerlocked) API so that when the webpage requests the pointer lock, the view controller uses that API to lock the mouse pointer. While the pointer is locked by the view controller, regular mouse events don't behave correctly on the web view, so the `GameController` framework is used to listen for mouse events and dispatch appropriate synthetic events to the pointer locked element in the web app.

Additionally, unlike the regular web app shortcut, this will display the stream completely full-screen, without taking the safe area into account. While the pointer is locked, the home indicator and status bar will be hidden as well.

# 2. Running

You will need to build and deploy this using Xcode on a mac.

# 3. Limitations

The usual `prefersPointerLocked` limitations apply. The app must not be in split view, slide over or covered by a slide over app; in stage manager it must be the only app on screen.

The escape key is reserved for releasing the pointer lock. To send an escape key to the game, you need to double press it - the first one ends the pointer lock and the second one is sent to the game - then click on the game to acquire the pointer lock again.

# 4. License

[MIT License](LICENSE.MD)
