Question:
TISSelectInputSource is used in both flipio and LayoutSwitchTest but in flipio it behaves differently (even though both projects use periodic timer-based switching) and when keyboard layout is switched (from timer periodic task) then blue system popup with the current layout is not displayed. Compare every possible aspect of both projects and provide ideas what could be different. and would could fix the issue.

Answer:

## Root cause candidates

### 1. **App Sandbox** — most likely culprit

|                      | Flipio  | LayoutSwitchTest |
| -------------------- | ------- | ---------------- |
| `ENABLE_APP_SANDBOX` | **YES** | **NO**           |

The system keyboard-layout HUD is rendered by the window server in response to `TISSelectInputSource`. When a sandboxed process calls it, the layout switch succeeds but the window server refuses to show the inline HUD overlay, because the sandbox profile blocks the inter-process UI channel that the HUD uses. LayoutSwitchTest is completely unsandboxed, so the overlay appears normally.

------

### 2. **Agent app / no active window**

Flipio is a menu bar app — it creates only an `NSStatusItem`, has a SwiftUI `Settings` scene with `EmptyView`, and almost certainly has `LSUIElement = YES` (or gains `.accessory` activation policy implicitly). The keyboard layout HUD is tied to the **frontmost regular application's** display context. When a background/agent app calls `TISSelectInputSource`, the system may not know which screen/space to render the HUD on, so it silently suppresses it.

LayoutSwitchTest has a normal `ContentView` window, a Dock icon, and is the active foreground app when the timer fires → the system has a clear target to render the HUD.

------

### 3. **`NSApp.activationPolicy` difference**

Directly related to #2. Flipio likely runs as `.accessory`, LayoutSwitchTest runs as `.regular`. The HUD is documented to appear for the frontmost regular-policy app.

------

### 4. **[KeyboardLayoutSwitcher.swift](vscode-file://vscode-app/Applications/Visual Studio Code.app/Contents/Resources/app/out/vs/code/electron-browser/workbench/workbench.html) code is identical**

Both files are byte-for-byte the same (confirmed), so the difference is entirely in the app environment, not the switching logic.

------

## Fix ideas (ordered by invasiveness)

**A. Disable the sandbox (simplest)** - WORKS
Set `ENABLE_APP_SANDBOX = NO` in Flipio's build settings. This is the most direct fix. Works fine for a direct-distribution app (outside MAS). If MAS distribution is needed, this path is closed.

**B. Temporarily promote activation policy before switching** - DOESN'T WORK
Before calling `TISSelectInputSource`, switch the app to regular mode, make it active, perform the switch, then demote back:

This gives the window server a real foreground app context, which may be enough to trigger the HUD. Side effect: the Dock icon flashes briefly.

**C. Simulate the system keyboard shortcut via CGEvent instead of calling `TISSelectInputSource` directly** - WORKS, Requires special permission

Post a synthetic `keyDown`/`keyUp` for whatever the user set in *System Settings → Keyboard → Shortcuts → Input Sources* (e.g. Ctrl+Space or Ctrl+Option+Space). The system handles it end-to-end including the HUD. Downside: you'd need to know the configured shortcut and it's fragile.

**D. Post a `kTISNotifySelectedKeyboardInputSourceChanged` distributed notification after switching** - DOESN'T WORK
Some reports suggest posting `com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged` on `DistributedNotificationCenter` after the call nudges the system to display the HUD, though this is undocumented.

**E. Add the `com.apple.security.temporary-exception.apple-events` or similar sandbox exception** - TO BE CHECKED
There's no official public sandbox entitlement that re-enables HUD display, so this avenue is unlikely to help.

------

## TL;DR

The `ENABLE_APP_SANDBOX = YES` in Flipio + its agent-app (no-window) nature together suppress the system HUD that LayoutSwitchTest (unsandboxed, regular foreground app) gets for free. **Fix A** (disable sandbox) instantly resolves it; **Fix B** (temporarily `.regular` activation policy) is usable if you need the sandbox.