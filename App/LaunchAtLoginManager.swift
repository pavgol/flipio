//
//  LaunchAtLoginManager.swift
//  Flipio
//
//  Created by Pavel Golub on 13/02/2026.
//

import Foundation
import Combine
import ServiceManagement
import os

class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()
    
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "launchAtLogin")
            applyLaunchAtLoginSetting()
        }
    }
    
    private let logger = Logger(subsystem: "com.flipio.app", category: "LaunchAtLogin")
    
    private init() {
        // Check if the preference exists, if not set it to true (enabled by default)
        if UserDefaults.standard.object(forKey: "launchAtLogin") == nil {
            UserDefaults.standard.set(true, forKey: "launchAtLogin")
            self.isEnabled = true
        } else {
            self.isEnabled = UserDefaults.standard.bool(forKey: "launchAtLogin")
        }
        
        // Apply the setting on initialization
        applyLaunchAtLoginSetting()
    }
    
    private func applyLaunchAtLoginSetting() {
        do {
            if isEnabled {
                if SMAppService.mainApp.status == .enabled {
                    logger.info("Launch at login already enabled")
                } else {
                    try SMAppService.mainApp.register()
                    logger.info("Launch at login enabled successfully")
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                    logger.info("Launch at login disabled successfully")
                } else {
                    logger.info("Launch at login already disabled")
                }
            }
        } catch {
            logger.error("Failed to update launch at login setting: \(error.localizedDescription)")
        }
    }
}
