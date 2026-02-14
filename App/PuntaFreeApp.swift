//
//  FlipioApp.swift
//  Flipio
//
//  Created by Pavel Golub on 31/01/2026.
//

import SwiftUI
import os

@main
struct FlipioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    static let logger = Logger(subsystem: "com.flipio.app", category: "main")
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
