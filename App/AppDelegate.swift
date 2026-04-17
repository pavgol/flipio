//
//  AppDelegate.swift
//  Flipio
//
//  Created by Pavel Golub on 13/02/2026.
//

import SwiftUI
import AppKit
import os

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Set up the menu bar icon - using custom icon from assets
        if let button = statusItem.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.image?.isTemplate = true  // Enable template rendering for automatic light/dark mode
            button.imagePosition = .imageLeading
        }
        
        // Create the menu
        setupMenu()
        
        // Check accessibility permissions on startup using centralized manager
        Task { @MainActor in
            let permissionManager = AccessibilityPermissionManager.shared
            if !permissionManager.isAccessibilityGranted {
                openPrefs()
            }
        }
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        // Settings menu item
        let settingsItem = NSMenuItem(
            title: "Settings",
            action: #selector(openPrefs),
            keyEquivalent: ""
        )
        settingsItem.target = self
        settingsItem.image = nil
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit menu item
        let quitItem = NSMenuItem(
            title: "Quit Flipio",
            action: #selector(quitApp),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc private func openPrefs() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let settingsView = SettingsWindow()
        
        let hostingController = NSHostingController(rootView: settingsView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Flipio Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 450, height: 550))
        window.center()
        window.isReleasedWhenClosed = false
        
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func quitApp() {
        EventMonitor.shared.stop()
        NSApplication.shared.terminate(nil)
    }
}
