//
//  AccessibilityPermissionManager.swift
//  Flipio
//
//  Created by Pavel Golub on 14/02/2026.
//

import SwiftUI
import Combine
import ApplicationServices
import os

/// Centralized manager for tracking accessibility permission state
@MainActor
class AccessibilityPermissionManager: ObservableObject {
    static let shared = AccessibilityPermissionManager()
    
    @Published private(set) var isAccessibilityGranted = false
    private var timer: Timer?
    private var checkCount = 0
    
    private init() {
        // Check immediately on initialization
        checkAccessibilityPermission()
    }
    
    /// Check current accessibility permission status
    @discardableResult
    func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        checkCount += 1
        
        let status = trusted ? "GRANTED" : "DENIED"
        FlipioApp.logger.debug("Check #\(self.checkCount, privacy: .public): Accessibility permission = \(status, privacy: .public)")
        
        isAccessibilityGranted = trusted
        
        if trusted {
            stopPeriodicChecks()
            EventMonitor.shared.start()
        }
        
        return trusted
    }
    
    /// Start periodic checks (useful when waiting for user to grant permission)
    func startPeriodicChecks() {
        // Don't start if already granted
        guard !isAccessibilityGranted else {
            FlipioApp.logger.info("Accessibility permission already granted; periodic checks not started")
            return
        }
        
        // Avoid multiple timers
        guard timer == nil else { return }
        
        // Check every 3 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAccessibilityPermission()
            }
        }
        
        FlipioApp.logger.info("Started periodic accessibility permission checks (every 3 seconds)")
    }
    
    /// Stop periodic checks
    func stopPeriodicChecks() {
        guard timer != nil else { return }
        
        timer?.invalidate()
        timer = nil
        FlipioApp.logger.info("Stopped periodic accessibility permission checks")
    }
}
