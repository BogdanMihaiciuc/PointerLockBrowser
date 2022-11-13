// This file is not used directly by the pointer lock shim,
// but it declares globals that typescript is unaware of
// and prevents it from complaining about them

declare var ApplePaySession: any;

declare var webkit;

interface Event {
    _isWKPointerEvent?: boolean;
}