// @ts-check

//#region Browser detection

Object.defineProperty(navigator, 'standalone', {value: true});

// Make GFN think it's a windows desktop
Object.defineProperty(navigator, 'platform', {value: 'Windows'});
Object.defineProperty(navigator, 'vendor', {value: 'Google Inc.'});

// GFN uses this to verify if the platform is safari, which disables
// keyboard and mouse games
window.ApplePaySession = undefined;

// GFN uses the voice URI to verify if the platform is Chrome/Chome OS/Android
// which is a good fallback because an unrecognized browser disables all games
// NOTE: This does prevent speech synthethis from working but it is not actually used
let _WKGetVoices = window.speechSynthesis.getVoices;
//@ts-ignore
window.speechSynthesis.getVoices = function () {
    const result = [];

    result.push({voiceURI: 'Google'});
    result.push({voiceURI: 'android'});

    return result;
}

//#endregion

//#region Fullscreen

// Entering fullscreen doesn't quite work, so disable it, but make it appear
// as if it worked; the video stream is already essentially fullscreen

/**
 * The current fullscreen element.
 * @type {Element | undefined}
 */
let _WKFullScreenElement;

Element.prototype.requestFullscreen = async function () {
    _WKFullScreenElement = this;
}

Document.prototype.exitFullscreen = async function () {
    _WKFullScreenElement = undefined;
}

Object.defineProperty(document, 'fullscreenElement', {
    get() {
        return _WKFullScreenElement;
    }
});

//#endregion

//#region Pointer lock

/**
 * The element requesting pointer lock.
 * 
 * When the system disables the pointer lock (e.g. due to switching to another app)
 * this represents the element that originally requested the pointer lock.
 * @type {Element | undefined}
 */
let _WKPointerLockRequestingElement;

/**
 * The element that currently has the pointer lock.
 * @type {Element | undefined}
 */
let _WKPointerLockElement;

// Fill in request pointer lock if it doesn't exist
Element.prototype.requestPointerLock = Element.prototype.requestPointerLock || function () {
    _WKPointerLockRequestingElement = this;
    webkit.messageHandlers.pointerLockHandler.postMessage("requestPointerLock");
}

// Fill in exit pointer lock if it doesn't exist
Document.prototype.exitPointerLock = Document.prototype.exitPointerLock || function () {
    _WKPointerLockRequestingElement = undefined;
    webkit.messageHandlers.pointerLockHandler.postMessage("exitPointerLock");
}

// Fill in the getter for the pointer lock element if it doesn't exist
if (!Object.getOwnPropertyDescriptor(Document.prototype, 'pointerLockElement')) {
    Object.defineProperty(Document.prototype, 'pointerLockElement', {
        get() {
            return _WKPointerLockElement;
        }
    })
}

/**
 * An array containing the pointer events that are converted into synthetic events
 * while the pointer is locked.
 * @type {[
    'mousedown', 'mouseup', 'mousemove',
    'click', 'dblclick', 'contextmenu',
    'pointerdown', 'pointerup', 'pointermove',
    'wheel'
]}
 */
const _WKHandledPointerEvents = [
    'mousedown', 'mouseup', 'mousemove',
    'click', 'dblclick', 'contextmenu',
    'pointerdown', 'pointerup', 'pointermove',
    'wheel'
];

/**
 * Invoked by WebKit when the pointer lock state changes.
 * @param state     `true` if the pointer is locked, `false` otherwise.
 */
function _WKPointerLockStateDidChange(state) {
    if (state) {
        // When the pointer is locked, set the locked element to the requesting one
        _WKPointerLockElement = _WKPointerLockRequestingElement;

        // Retain the requesting element because, if the system takes the pointer lock away
        // it restores it when the app becomes the first responder again

        // When locking the pointer, create synthetic events for all mouse events
        _WKHandledPointerEvents.forEach(name => {
            window.addEventListener(name, _WKPointerEventHandler, {capture: true});
        });

        // Disable standard pointer events, because regular mousedown, click and mouseup
        // events are still sent to the webview, which causes the pointer to jump around
        // because they still contain the x and y coordinates
        document.documentElement.style.pointerEvents = 'none';
    }
    else {
        // When the pointer is unlocked, clear the locked element
        _WKPointerLockElement = undefined;

        // Stop creating synthetic events for all mouse events when the pointer is unlocked
        _WKHandledPointerEvents.forEach(name => {
            window.removeEventListener(name, _WKPointerEventHandler, {capture: true});
        });

        // Reenable standard pointer events
        document.documentElement.style.pointerEvents = '';
    }

    // Regardless of the state, a pointerlockchange event needs to be dispatched to the document
    const event = new Event("pointerlockchange");
    document.dispatchEvent(event);
}

/**
 * Invoked whenever the mouse moves while the pointer is locked.
 * @param {number} deltaX       The movement on the X axis.
 * @param {number} deltaY       The movement on the Y axis.
 */
function _WKPointerDidMove(deltaX, deltaY) {
    const event = new MouseEvent('mousemove', {
        clientX: 0,
        screenX: 0,
        movementX: deltaX,

        clientY: 0,
        screenY: 0,
        movementY: deltaY,

        view: window,
        bubbles: true,
        cancelable: true,
    });

    Object.defineProperty(event, 'movementX', {value: deltaX});
    Object.defineProperty(event, 'movementY', {value: deltaY});
    Object.defineProperty(event, '_isWKPointerEvent', {value: true});

    if (document.pointerLockElement) {
        document.pointerLockElement.dispatchEvent(event);
    }

    // Also dispatch a pointer move event
    const pointerEvent = new PointerEvent('pointermove', {
        clientX: 0,
        screenX: 0,
        movementX: deltaX,

        clientY: 0,
        screenY: 0,
        movementY: deltaY,

        view: window,
        bubbles: true,
        cancelable: true,

        pointerId: 1,
        pointerType: 'mouse',
        isPrimary: true,
    });

    Object.defineProperty(event, 'movementX', {value: deltaX});
    Object.defineProperty(event, 'movementY', {value: deltaY});
    Object.defineProperty(event, '_isWKPointerEvent', {value: true});

    Object.defineProperty(pointerEvent, 'movementX', {value: deltaX});
    Object.defineProperty(pointerEvent, 'movementY', {value: deltaY});
    Object.defineProperty(pointerEvent, '_isWKPointerEvent', {value: true});

    if (document.pointerLockElement) {
        document.pointerLockElement.dispatchEvent(event);
        document.pointerLockElement.dispatchEvent(pointerEvent);
    }
}

/**
 * An object that maps the pointer button values to their bitfield values
 * for the `buttons` property.
 */
const _WKButtonBitMap = {
    0: 1,
    1: 4,
    2: 2,
    3: 8,
    4: 16
}

/**
 * Invoked whenever the pointer scrolls while pointer lock is active.
 * @param {number} dx           The scroll amount on the X axis.
 * @param {number} dy           The scroll amount on the Y axis.
 */
 function _WKPointerDidScroll(dx, dy) {
    // Create a synthetic event
    const wheelEvent = new WheelEvent('wheel', {
        clientX: 0,
        screenX: 0,
        movementX: 0,

        clientY: 0,
        screenY: 0,
        movementY: 0,

        view: window,
        bubbles: true,
        cancelable: true,

        buttons: _WKButtons,

        deltaX: dx,
        deltaY: dy,
        deltaZ: 0,
        deltaMode: 0
    });

    Object.defineProperty(wheelEvent, 'movementX', {value: 0});
    Object.defineProperty(wheelEvent, 'movementY', {value: 0});
    Object.defineProperty(wheelEvent, '_isWKPointerEvent', {value: true});

    // Dispatch it to the pointer lock element
    if (document.pointerLockElement) {
        document.pointerLockElement.dispatchEvent(wheelEvent);
    }
}

/**
 * Keeps track of the currently pressed buttons.
 */
let _WKButtons = 0;

/**
 * Invoked whenever the pressed state changes for any mouse button.
 * @param {number} button           The button whose press state changed.
 * @param {boolean} pressed         `true` if the button is pressed, `false` otherwise.
 */
function _WKPointerDidChangePressState(button, pressed) {
    let eventType;
    if (pressed) {
        // Select the appropriate event type
        eventType = 'mousedown';

        // Update the value of the buttons property
        _WKButtons |= _WKButtonBitMap[button];
    }
    else {
        eventType = 'mouseup';
        _WKButtons &= ~_WKButtonBitMap[button];
    }

    // Create a synthetic event
    const pointerEvent = new MouseEvent(eventType, {
        clientX: 0,
        screenX: 0,
        movementX: 0,

        clientY: 0,
        screenY: 0,
        movementY: 0,

        view: window,
        bubbles: true,
        cancelable: true,

        button: button,
        buttons: _WKButtons,
    });

    Object.defineProperty(pointerEvent, 'movementX', {value: 0});
    Object.defineProperty(pointerEvent, 'movementY', {value: 0});
    Object.defineProperty(pointerEvent, '_isWKPointerEvent', {value: true});

    // Dispatch it to the pointer lock element
    if (document.pointerLockElement) {
        document.pointerLockElement.dispatchEvent(pointerEvent);
    }
}

/**
 * A handler for all mouse/pointer events while pointer lock is enabled,
 * that stops propagation of all events since they are dispatched via the
 * game controller framework instead.
 * @param {MouseEvent | PointerEvent} event    The original mouse event.
 */
function _WKPointerEventHandler(event) {
    // If this event is already a synthetic event, don't process it
    if (event._isWKPointerEvent) {
        return;
    }

    // If this event is a mousemove event, ensure that it has the movement properties
    if (event.type == 'mousemove' || event.type == 'pointermove') {
        Object.defineProperty(event, 'movementX', {value: event.movementX || 0});
        Object.defineProperty(event, 'movementY', {value: event.movementX || 0});
        return;
    }

    // Otherwise prevent this event from triggering any action or propagating to any element
    event.stopImmediatePropagation();
    event.preventDefault();

}

//#endregion
