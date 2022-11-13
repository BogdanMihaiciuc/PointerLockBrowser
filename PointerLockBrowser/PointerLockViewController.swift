//
//  ViewController.swift
//  PointerLockBrowser
//
//  Created by Bogdan Mihaiciuc on 02.11.2022.
//

import UIKit
import WebKit
import GameController

extension Constants {
    /**
     * The name of the handler that is responsible for implementing pointer lock.
     */
    public static let PointerLockHandlerName = "pointerLockHandler";
    
    /**
     * The body of the message used to request pointer lock for an element.
     */
    public static let RequestPointerLockMessage = "requestPointerLock";
    
    /**
     * The body of the message used to unlock the pointer for the document.
     */
    public static let ExitPointerLockMessage = "exitPointerLock";
}

/**
 * A view controller that contains a web view that loads the `Constants.WebAppURL` URL and allows
 * the presented webpage to use the pointer lock API, by using UIKit's `prefersPointerLocked` API and
 * GameController to dispatch synthetic mouse events to the pointer locked element.
 *
 * While the pointer is locked, the view controller will also hide the status bar and home indicator.
 */
class PointerLockViewController: UIViewController, WKScriptMessageHandlerWithReply, WKUIDelegate {

    /**
     * The web view displaying the main content.
     */
    var webView: WebView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Create a configuration that specifies a handler for the pointer lock requests
        let configuration = WKWebViewConfiguration();
        configuration.userContentController.addScriptMessageHandler(self, contentWorld: WKContentWorld.page, name: "pointerLockHandler");
        
        // Load the user script that shims pointer lock
        guard let path = Bundle.main.path(forResource: "PointerLockShim", ofType: "js") else {
            NSException.raise(NSExceptionName("InaccessibleResourceException"), format: "Unable to load the pointer lock shim resource.", arguments: getVaList([]));
            return;
        }
        let script = try! String(contentsOfFile: path);
        let userScript = WKUserScript(source: script, injectionTime: WKUserScriptInjectionTime.atDocumentStart, forMainFrameOnly: false);
        configuration.userContentController.addUserScript(userScript);
        
        // This is required for service workers to be loaded
        configuration.limitsNavigationsToAppBoundDomains = true;
        
        // Configure media settings
        configuration.allowsInlineMediaPlayback = true;
        configuration.mediaTypesRequiringUserActionForPlayback = [];
        configuration.allowsPictureInPictureMediaPlayback = true;
        configuration.suppressesIncrementalRendering = false;
        
        // Allow requesting full screen, this will be then shimmed in javascript
        let preferences = WKPreferences();
        preferences.isElementFullscreenEnabled = true;
        preferences.javaScriptCanOpenWindowsAutomatically = true;
        configuration.preferences = preferences;
        
        // Create the web view that will display the web app
        webView = WebView(frame: CGRectMake(0, 0, 0, 0), configuration: configuration);
        view.addSubview(webView);
        
        // Position the web view to take up the entire window
        webView.translatesAutoresizingMaskIntoConstraints = false;
        webView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true;
        webView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true;
        webView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true;
        webView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true;
        
        webView.uiDelegate = self;
        
        // Identify as Chrome
        webView.customUserAgent = "Mozilla/5.0 (X11; CrOS aarch64 13099.85.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/84.0.4147.110 Safari/537.36";
        
        // Load the web app
        let request = URLRequest(url: URL(string: Constants.WebAppURL)!);
        webView.load(request);
        
        // Listen for the pointer lock state change notification to relay that information
        // to the web app
        NotificationCenter.default.addObserver(self, selector: #selector(self._pointerLockDidChange(_:)), name: UIPointerLockState.didChangeNotification, object: nil)
        
        // Listen for a mouse getting connected
        NotificationCenter.default.addObserver(self, selector: #selector(self._mouseDidConnect(_:)), name: NSNotification.Name.GCMouseDidConnect, object: nil);
        
    }
    
    // MARK: Pointer lock
    
    /**
     * Controls whether pointer lock should be requested.
     */
    private var _pointerLockRequested = false;
    
    override var prefersPointerLocked: Bool {
        return _pointerLockRequested;
    }
    
    override var prefersStatusBarHidden: Bool {
        // While the pointer is locked, hide the status bar
        return _pointerLockRequested;
    }
    
    override var prefersHomeIndicatorAutoHidden: Bool {
        // While the pointer is locked, hide the home indicator
        return _pointerLockRequested;
    }
    
    /**
     * Used to determine whether the pointer is currently locked.
     */
    private var _pointerLocked = false;
    
    /**
     * Invoked when the pointer lock state changes for this scene.
     * Sends an appropriate message to the web app so that it also enables the pointer lock.
     */
    @objc private func _pointerLockDidChange(_ notification: NSNotification) -> Void {
        let scene = notification.userInfo?[UIPointerLockState.sceneUserInfoKey] as? UIScene;
        let isLocked = scene!.pointerLockState!.isLocked;
        _pointerLocked = isLocked;
        
        // Regardless of the state, the web app should receive a pointerlockchange event
        webView.evaluateJavaScript("_WKPointerLockStateDidChange(\(isLocked ? "true" : "false"))");
    }
    
    // MARK: Webview content handler
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        
        // Only respond to messages sent to the "pointerLock" handler.
        if (message.name != Constants.PointerLockHandlerName) {
            replyHandler(nil, "Unknown message handler: \"\(message.name)\"");
            return;
        }
        
        switch (message.body as? String) {
            
        case Constants.RequestPointerLockMessage:
            // Switch to prefer pointer locked
            _pointerLockRequested = true;
            self.setNeedsUpdateOfPrefersPointerLocked();
            self.setNeedsUpdateOfHomeIndicatorAutoHidden();
            self.setNeedsStatusBarAppearanceUpdate();
            
            replyHandler(NSNull(), nil);
            
        case Constants.ExitPointerLockMessage:
            // Switch to prefer pointer unlocked
            _pointerLockRequested = false;
            self.setNeedsUpdateOfPrefersPointerLocked();
            self.setNeedsUpdateOfHomeIndicatorAutoHidden();
            self.setNeedsStatusBarAppearanceUpdate();
            
            replyHandler(NSNull(), nil);
            
        default:
            // Report an error when an unknown message is sent
            replyHandler(nil, "Unknown message sent: \"\(message.body)\"");
        }
        
    }
    
    // MARK: Pointer events
    
    /**
     * Invoked when a mouse is connected.
     * Sets up the move handler that dispatches the appropriate event to the web app.
     * Also sets up handlers for the mousedown/mouseup events for all of the mouse's buttons.
     */
    @objc private func _mouseDidConnect(_ notification: NSNotification) {
        let mouse = notification.object as? GCMouse;
        
        guard let input = mouse?.mouseInput else {
            return;
        }
        
        // Listen for mouse events
        weak var weakController = self;
        input.mouseMovedHandler = {(mouse, deltaX, deltaY) in
            guard let strongController = weakController else {
                return;
            }
            
            // When the pointer is locked, dispatch those events to the web app
            if (strongController._pointerLocked) {
                // In uikit the sizes are in physical pixels, but in webkit they are in CSS pixels
                let scale = strongController.webView.window?.screen.scale ?? 1;
                
                let dx = CGFloat(deltaX) / scale;
                // Webkit and uikit use opposite axis directions for the y axis
                let dy = CGFloat(-deltaY) / scale;
                
                strongController.webView.evaluateJavaScript("_WKPointerDidMove(\(dx), \(dy))");
            }
            
        }
        
        // Listen for wheel/trackpad events
        input.scroll.valueChangedHandler = {(scroll, deltaX, deltaY) in
            guard let strongController = weakController else {
                return;
            }
            
            if (strongController._pointerLocked) {
                // Dispatch an appropriately scaled wheel event to the web app
                let scale = strongController.webView.window?.screen.scale ?? 1;
                
                // NOTE: It appears that the x and y coordinates are swapped
                let dx = CGFloat(deltaY) / scale;
                let dy = CGFloat(deltaX) / scale;
                
                strongController.webView.evaluateJavaScript("_WKPointerDidScroll(\(dx), \(dy))");
            }
        }
        
        /**
         * Sets up the pointer down/up event generation for the specified mouse button, corresponding to the
         * specified javascript button identifier.
         * @param button             The button input which will provide the events.
         * @param jsButton          An integer that specifies the corresponding javasciprt button value to use for the event.
         */
        func setUpPointerDown(button: GCControllerButtonInput, jsButton: Int) {
            button.pressedChangedHandler = {(_, _, pressed) in
                guard let strongController = weakController else {
                    return;
                }
                
                if (strongController._pointerLocked) {
                    // Dispatch an event for the pointer state change event for the appropriate javascript button value
                    strongController.webView?.evaluateJavaScript("_WKPointerDidChangePressState(\(jsButton), \(pressed))");
                }
            }
        }
        
        // Set up the pointer down/up events for all mouse buttons
        setUpPointerDown(button: input.leftButton, jsButton: 0);
        if let middleButton = input.middleButton {
            setUpPointerDown(button: middleButton, jsButton: 1);
        }
        if let rightButton = input.rightButton {
            setUpPointerDown(button: rightButton, jsButton: 2);
        }
        
        // Also include auxiliary buttons if they exist
        var jsAuxiliaryButtonValue = 3;
        input.auxiliaryButtons?.forEach({ (button: GCControllerButtonInput) in
            setUpPointerDown(button: button, jsButton: jsAuxiliaryButtonValue);
            jsAuxiliaryButtonValue += 1;
        })
        
    }

    // MARK: Disable context menus
    
    func webView(_ webView: WKWebView, contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo, completionHandler: @escaping (UIContextMenuConfiguration?) -> Void) {
        completionHandler(nil);
    }
    
    override var canBecomeFirstResponder: Bool {
        return true;
    }
    
    override var canResignFirstResponder: Bool {
        // While the pointer is locked, prevent the view controller from resigning first responder;
        // this will prevent the context menu from appearing when right clicking, to avoid interrupting
        // the game
        return !_pointerLocked;
    }
    
    // MARK: Support window.open
    
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let webView = WKWebView(frame: CGRectZero, configuration: configuration);
        
        // TODO: Render a close button when the toolbar window feature is enabled
        
        view.addSubview(webView);
        
        // Position the web view to take up the entire window
        webView.translatesAutoresizingMaskIntoConstraints = false;
        webView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true;
        webView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true;
        webView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true;
        webView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true;
        
        return webView;
    }
    
}

