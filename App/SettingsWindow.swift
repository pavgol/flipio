//
//  SettingsWindow.swift
//  Flipio
//
//  Created by Pavel Golub on 13/02/2026.
//

import SwiftUI
import AppKit
import ApplicationServices
import os

struct SettingsWindow: View {
    @ObservedObject private var permissionManager = AccessibilityPermissionManager.shared
    @StateObject private var launchAtLoginManager = LaunchAtLoginManager.shared
    
    var body: some View {
        Group {
            if !permissionManager.isAccessibilityGranted {
                // Show the new permission request screen
                AccessibilityPermissionView()
            } else {
                // Show success/info view when permission is granted
                permissionGrantedView
            }
        }
    }
    
    private var permissionGrantedView: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Flipio")
                    .font(.system(size: 24, weight: .semibold))
                
                
            }
            .padding(.top, 30)
            .padding(.bottom, 20)
            
            // Main Content
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How it works:")
                            .font(.headline)
                        Text("Press ⌥ Option in any app to convert selected text or last word between keyboard layouts.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        HStack {
                            Text("htgf")
                                .font(.system(.body, design: .monospaced))
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("репа")
                                .font(.system(.body, design: .monospaced))
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 8)
                }
                
                Section {
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Launch at Login")
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                            
                            Text("Automatically start Flipio when you log in to your Mac.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $launchAtLoginManager.isEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .focusable(false)
                    }
                    
                } header: {
                    Text("General")
                        .font(.headline)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            
            Spacer()
            
            // Footer note
            HStack(spacing: 8) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("Accessibility Access Granted")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 20)
        }
        .frame(minWidth: 450, minHeight: 550)
    }
}

#Preview {
    SettingsWindow()
}
