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
        // Start continuous monitoring to detect permission revocation
        startContinuousMonitoring()
    }
    
    /// Check current accessibility permission status
    @discardableResult
    func checkAccessibilityPermission() -> Bool {
        let previousStatus = isAccessibilityGranted
        let trusted = AXIsProcessTrusted()
        checkCount += 1
        
        let status = trusted ? "GRANTED" : "DENIED"
        FlipioApp.logger.debug("Check #\(self.checkCount, privacy: .public): Accessibility permission = \(status, privacy: .public)")
        
        isAccessibilityGranted = trusted
        
        // Handle permission state changes
        if trusted && !previousStatus {
            // Permission just granted
            FlipioApp.logger.info("Accessibility permission granted - starting EventMonitor")
            EventMonitor.shared.start()
        } else if !trusted && previousStatus {
            // Permission just revoked - CRITICAL: stop monitoring immediately to prevent system hang
            FlipioApp.logger.warning("Accessibility permission REVOKED - stopping EventMonitor immediately")
            EventMonitor.shared.stop()
        }
        
        return trusted
    }
    
    /// Start continuous monitoring that runs forever to detect permission changes
    private func startContinuousMonitoring() {
        // Avoid multiple timers
        guard timer == nil else { return }
        
        // Check every 3 seconds continuously
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAccessibilityPermission()
            }
        }
        
        FlipioApp.logger.info("Started continuous accessibility permission monitoring (every 3 seconds)")
    }

}
