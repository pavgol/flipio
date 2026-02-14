//
//  FlipioApp.swift
//  Flipio
//
//  Created by Pavel Golub on 31/01/2026.
//

import SwiftUI
import os

/// Value stored in `.eventSourceUserData` for synthetic events created by Flipio.
/// Keep in sync anywhere we need to recognize or set this tag.
let FlipioSyntheticEventUserData: Int64 = 0x464C4950 // 'FLIP'

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
