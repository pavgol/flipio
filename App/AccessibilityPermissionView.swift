//
//  AccessibilityPermissionView.swift
//  Flipio
//
//  Created by Pavel Golub on 13/02/2026.
//

import SwiftUI
import AppKit

struct AccessibilityPermissionView: View {
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header Section
                HeaderSection()
                    .padding(.top, 32)
                    .padding(.horizontal, 32)
                
                Spacer(minLength: 32)
                
                // Primary Action
                Button(action: openSystemPreferences) {
                    Label("Open System Settings", systemImage: "gearshape.fill")
                        .font(.body)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.accentColor)
                .keyboardShortcut(.defaultAction)
                
                Spacer(minLength: 24)
                
                // Instructions and Icon
                InstructionsSection()
                    .padding(.horizontal, 32)
                
                Spacer(minLength: 24)
                
                // Help Section
                Divider()
                    .padding(.horizontal, 32)
                
                Button(action: showHelp) {
                    Label("Need help?", systemImage: "questionmark.circle")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.vertical, 16)
            }
        }
    }
    
    private func openSystemPreferences() {
        // Open System Settings to Accessibility preferences
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "How to Grant Accessibility Access"
        alert.informativeText = """
        1. Click "Open System Settings" to open System Settings
        2. Navigate to Privacy & Security → Accessibility
        3. Drag the Flipio icon into the list, or click the + button
        4. Enable the toggle next to Flipio
        5. Restart the app if needed
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - Subviews

private struct HeaderSection: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Accessibility Permission Required")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            
            Text("Grant access to enable text conversions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct InstructionsSection: View {
    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Flipio"
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Instructions text
            VStack(spacing: 8) {
                Text("Then:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .fontWeight(.medium)
                
                Text("Drag this icon to **Privacy & Security** → **Accessibility**")
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // App Icon - Draggable
            VStack(spacing: 10) {
                if let appIcon = NSApplication.shared.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 96, height: 96)
                        .clipShape(.rect(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
                        )
                        .onDrag {
                            let bundleURL = Bundle.main.bundleURL
                            return NSItemProvider(object: bundleURL as NSURL)
                        }
                        .help("Drag this icon to System Settings > Privacy & Security > Accessibility")
                        .accessibilityLabel("Application icon, draggable to System Settings")
                }
                
                // App name badge
                Text(appName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.accentColor)
                    )
            }
            .padding(.vertical, 16)
        }
    }
}

#Preview {
    AccessibilityPermissionView()
        .frame(width: 600, height: 600)
}
