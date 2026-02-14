//
//  OptionTapDetector.swift
//  Flipio
//
//  Pure state machine for detecting a single Option key "tap":
//  press and release within a timeout, with no other key pressed in between.
//

import ApplicationServices
import Foundation
import QuartzCore
import os

/// Detects a single Option key "tap" gesture: press and release within a timeout,
/// with no other key pressed in between.
final class OptionTapDetector {
    private var lastFlags: CGEventFlags = []
    private var optionTapPending = false
    private var optionTapTime: CFTimeInterval = 0
    private var otherKeyPressedSinceOptionDown = false
    private let timeout: CFTimeInterval
    
    init(timeout: CFTimeInterval = 0.35) {
        self.timeout = timeout
    }
    
    /// Processes a flags-changed event. Returns `true` when a valid Option tap is detected.
    func isShortcutTriggered(newFlags: CGEventFlags) -> Bool {
        let hadOption = lastFlags.contains(.maskAlternate)
        let hasOption = newFlags.contains(.maskAlternate)
        lastFlags = newFlags
        
        if hasOption && !hadOption {
            // Option key pressed down
            optionTapPending = true
            optionTapTime = CACurrentMediaTime()
            otherKeyPressedSinceOptionDown = false
            FlipioApp.logger.debug("Option DOWN → tap pending")
            return false
        }
        
        guard !hasOption && hadOption else {
            // Other modifier change (not Option)
            return false
        }
        
        // Option key released - check if it was a valid tap
        let elapsed = CACurrentMediaTime() - optionTapTime
        let isValidTap = optionTapPending
        && !otherKeyPressedSinceOptionDown
        && elapsed <= timeout
        
        optionTapPending = false
        
        if isValidTap {
            FlipioApp.logger.debug("Option UP (held \(String(format: "%.2f", elapsed))s) → tap detected")
            return true
        }
        
        // Log cancellation reason
        if otherKeyPressedSinceOptionDown {
            FlipioApp.logger.debug("Option UP → tap cancelled (other key pressed)")
        } else {
            FlipioApp.logger.debug("Option UP (held \(String(format: "%.2f", elapsed))s) → tap cancelled (timeout)")
        }
        
        return false
    }
    
    /// Notifies that a key was pressed. Cancels any pending Option tap.
    func reset() {
        otherKeyPressedSinceOptionDown = true
    }
}
