//
//  WebView.swift
//  PointerLockBrowser
//
//  Created by Bogdan Mihaiciuc on 02.11.2022.
//

import UIKit
import WebKit

/**
 * A subclass of `WKWebView` that prevents the right click menu from appearing, which interferes with
 * the pointer lock and also prevents right clicks from being properly handled by the web app.
 */
class WebView : WKWebView {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return false;
    }
}
