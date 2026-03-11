import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

/// Performs layout conversion on the currently selected text by:
/// 1. Remembering the current clipboard contents.
/// 2. Synthesizing a Cmd+C (copy) for the frontmost app.
/// 3. Converting the copied text via `LayoutConverter`.
/// 4. Temporarily replacing the clipboard with the converted text.
/// 5. Synthesizing a Cmd+V (paste) to replace the selection.
/// 6. Restoring the original clipboard contents.
///
/// It also supports a "typed word" flow where we:
/// 1. Use the already-built buffer of the last word the user typed.
/// 2. Convert that word via `LayoutConverter`.
/// 3. Send backspace events to delete the original word.
/// 4. Temporarily put the converted word into the clipboard.
/// 5. Paste it at the caret, and then restore the original clipboard.
///
/// If no text ends up in the clipboard after Copy, the operation is a no-op.
final class TextConversionService: @unchecked Sendable {
    // Time intervals for clipboard operations
    private static let clipboardOperationDelay: TimeInterval = 0.05
    private static let backspaceProcessingDelay: TimeInterval = 0.2
    
    // NOTE: Text deletion strategy
    // Currently using select-and-delete (Shift+Left Arrow + Delete) universally as it works reliably across all apps.
    // Future consideration: Other strategies like repeatBackspace or repeatControlBackspace could be added
    // if specific applications require different approaches.
    
    private let converter = LayoutConverter()
    private let pasteboard = NSPasteboard.general
    private let typedWordBuffer: TypedWordBuffer
    
    init(typedWordBuffer: TypedWordBuffer) {
        self.typedWordBuffer = typedWordBuffer
    }
    
    func convert() {
        if let word = typedWordBuffer.getBuffer(), !word.isEmpty {
            // New typed word case: convert it in-place using cycle through all layouts.
            FlipioApp.logger.info(
                "Attempting typed-word conversion for \(word, privacy: .private(mask: .hash))"
            )
            
            let _ = replaceTypedWordWithNextLayout(original: word)
            
        }
        // selection text conversion
        else {
            FlipioApp.logger.info("Text buffer is empty, using selection mode")
            
            let isConverted = convertAndReplace()
            
            if !isConverted {
                FlipioApp.logger.notice("No conversion possible - playing system beep")
                NSSound.beep()
            }
        }
        
    }
    
    // there is some lag between the copy/paste event (CMD+C, CMD+V) and the actual clipboard update,
    // i.e. clipboard is actually updated with some lag (async), keyboard events are much faster 
    // so we need to wait a bit before doing anything what is relying on the new clipboard content.
    func convertAndReplace() -> Bool {        
        // Snapshot current clipboard so we can restore it later.
        let snapshot = snapshotPasteboard()
        
        // Capture the text content before copy operation to detect if anything was actually selected
        // BUG: There is one bug which is unknown how to handle properly.
        // If user uses VS Code and selected nothing and pressed CMD+V 
        // then VS Code copies entire line to clipboard so this logic fails because clipboard content is changed but there is actually nothing selected.
        //IDEAS: VS Code copies entire line and it ends with newline character. Not very relyable, additionally
        // we should check for instance that the text doesn't contain newline characters because if user selected multiple lines then it also can end with newline character.
        // Another idea is to check if user clicked quickly with mouse then most probably nothing was selected; or if user used arrow keys without Shift, then it is also most probably no selection. But all of these heuristics are not very reliable, so currently there is no solution for this edge case.
        let textBeforeCopy = pasteboard.string(forType: .string)
        
        // Ensure we always restore the original clipboard even on early return.
        defer {
            Thread.sleep(forTimeInterval: Self.clipboardOperationDelay)
            restorePasteboard(from: snapshot)
        }
        guard simulateCopy() else {
            FlipioApp.logger.error("convertAndReplace: failed to synthesize Cmd+C")
            return false
        }
        
        // Give the system a brief moment to place the copied text on the pasteboard.
        Thread.sleep(forTimeInterval: Self.clipboardOperationDelay)
        
        guard let originalText = pasteboard.string(forType: .string), !originalText.isEmpty else {
            FlipioApp.logger.debug(
                "convertAndReplace: no text in clipboard after copy - nothing to convert")
            return false
        }
        
        // Check if clipboard text actually changed - if not, nothing was selected
        if originalText == textBeforeCopy {
            FlipioApp.logger.debug(
                "convertAndReplace: clipboard text unchanged after copy - nothing was selected")
            return false
        }else{
            FlipioApp.logger.debug(
                "convertAndReplace: textBeforeCopy `\(textBeforeCopy ?? "", privacy: .private(mask: .hash))`, originalText `\(originalText, privacy: .private(mask: .hash))`")
        }
        
        guard let conversion = converter.convertWithTarget(originalText) else {
            FlipioApp.logger.warning("convertAndReplace: no keyboard layouts available")
            return false
        }
        let converted = conversion.text
        
        FlipioApp.logger.notice(
            "conversion: \(originalText, privacy: .private(mask: .hash)) → \(converted, privacy: .private(mask: .hash)) (\("clipboard", privacy: .public))"
        )
        
        pasteboard.clearContents()
        pasteboard.setString(converted, forType: .string)
        
        let originalText2 = pasteboard.string(forType: .string)
        FlipioApp.logger.debug("convertAndReplace: clipboard has `\(originalText2 ?? "nil", privacy: .private(mask: .hash))`")
        
        Thread.sleep(forTimeInterval: Self.clipboardOperationDelay)
        guard simulatePaste() else {
            FlipioApp.logger.error("convertAndReplace: failed to synthesize Cmd+V")
            return false
        }
        converter.applyTargetLayout(conversion.targetLayout)
        return true
    }
    
    /// Core primitive for typed-word scenarios: deletes `original` using
    /// select-and-delete (Shift+Left Arrow + Delete) and types the replacement.
    @discardableResult
    func replaceTypedWord(original: String) -> Bool {
        guard let conversion = converter.convertWithTarget(original) else {
            FlipioApp.logger.warning("replaceTypedWord: no keyboard layouts available")
            return false
        }
        let replacement = conversion.text
        
        FlipioApp.logger.notice(
            "replaceTypedWord: \(original, privacy: .private(mask: .hash)) → \(replacement, privacy: .private(mask: .hash))"
        )
        
        // Delete the original text using app-appropriate strategy
        deleteTypedText(count: original.count)

        // Type the replacement text character by character
        simulateTyping(replacement)

        converter.applyTargetLayout(conversion.targetLayout)
        
        FlipioApp.logger.debug(
            "replaceTypedWord: completed via delete+typing"
        )
        return true
    }
    
    /// Replaces typed word with next layout in cycle (for live typing).
    /// Cycles through all available layouts: A->B->C->A...
    @discardableResult
    func replaceTypedWordWithNextLayout(original: String) -> Bool {
        guard let conversion = converter.convertToNextLayout(original) else {
            FlipioApp.logger.warning("replaceTypedWordWithNextLayout: no keyboard layouts available")
            return false
        }
        let replacement = conversion.text
        
        FlipioApp.logger.notice(
            "replaceTypedWordWithNextLayout: \(original, privacy: .private(mask: .hash)) → \(replacement, privacy: .private(mask: .hash))"
        )
        
        // Delete the original text using app-appropriate strategy
        deleteTypedText(count: original.count)

        // Type the replacement text character by character
        simulateTyping(replacement)

        converter.applyTargetLayout(conversion.targetLayout)
        typedWordBuffer.set(conversion.text)
        
        FlipioApp.logger.debug(
            "replaceTypedWordWithNextLayout: completed via delete+typing"
        )
        return true
    }
    
    // MARK: - Clipboard snapshot / restore
    
    /// Snapshot of the entire pasteboard: each item is a map of type → raw Data.
    private typealias PasteboardSnapshot = [[NSPasteboard.PasteboardType: Data]]
    
    private func snapshotPasteboard() -> PasteboardSnapshot {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else {
            FlipioApp.logger.debug("snapshotPasteboard: pasteBoard is empty")
            return []
        }
        
        var snapshot: PasteboardSnapshot = []
        snapshot.reserveCapacity(items.count)
        
        for item in items {
            var typeData: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    typeData[type] = data
                }
            }
            snapshot.append(typeData)
        }
        
        FlipioApp.logger.debug("snapshotPasteboard: captured \(snapshot.count) items")
        return snapshot
    }
    
    private func restorePasteboard(from snapshot: PasteboardSnapshot) {
        // If snapshot is empty, just clear the current contents.
        pasteboard.clearContents()
        
        guard !snapshot.isEmpty else {
            FlipioApp.logger.debug("restorePasteboard: snapshot empty → cleared clipboard")
            return
        }
        
        var itemsToWrite: [NSPasteboardItem] = []
        itemsToWrite.reserveCapacity(snapshot.count)
        
        for typeData in snapshot {
            let item = NSPasteboardItem()
            for (type, data) in typeData {
                item.setData(data, forType: type)
            }
            itemsToWrite.append(item)
        }
        
        let wrote = pasteboard.writeObjects(itemsToWrite)
        // Small delay so the target app can consume the converted clipboard contents
        // before we restore the original clipboard snapshot.
        Thread.sleep(forTimeInterval: Self.clipboardOperationDelay)
        
        FlipioApp.logger.debug(
            "restorePasteboard: restored \(itemsToWrite.count) items (success=\(wrote))")
    }
    
    // MARK: - Synthetic key events
    
    /// Checks if Spotlight search is currently active by examining the window list.
    private func isSpotlightActive() -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        
        // Look for Spotlight window in the window list
        for window in windowList {
            if let ownerName = window[kCGWindowOwnerName as String] as? String,
               ownerName == "Spotlight" {
                FlipioApp.logger.debug("isSpotlightActive: Spotlight window detected")
                return true
            }
        }
        
        return false
    }
    
    /// Deletes typed text using the appropriate strategy for the current app.
    /// - simulateBackspaceViaSelection: for OneNote and apps where regular backspace doesn't work
    /// - simulateBackspace_v2: for Spotlight Search and apps that need Control+Backspace
    /// - simulateBackspace: default for most apps
    private func deleteTypedText(count: Int) {
        guard count > 0 else { return }
        
        // Check for Spotlight first (it's not a traditional app)
        if isSpotlightActive() {
            FlipioApp.logger.debug("deleteTypedText: using Control+Backspace for Spotlight")
            simulateBackspace_v2(count: count)
            return
        }
        
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier else {
            FlipioApp.logger.debug("deleteTypedText: cannot determine frontmost app, using default backspace")
            simulateBackspace(count: count)
            return
        }
        
        // Apps that need select-and-delete strategy (Shift+Left Arrow + Delete)
        let needsSelectionStrategy = [
            "com.microsoft.onenote.mac"  // Microsoft OneNote
            // Add more bundle identifiers here as needed
        ]
        
        // Apps that need Control+Backspace strategy
        let needsControlBackspace: [String] = [
            // Add bundle identifiers here as needed
        ]
        
        // Check for apps needing select-and-delete
        if needsSelectionStrategy.contains(bundleId) {
            FlipioApp.logger.debug("deleteTypedText: using select-and-delete for \(bundleId)")
            simulateBackspaceViaSelection(count: count)
        }
        // Check for apps needing Control+Backspace
        else if needsControlBackspace.contains(bundleId) {
            FlipioApp.logger.debug("deleteTypedText: using Control+Backspace for \(bundleId)")
            simulateBackspace_v2(count: count)
        }
        // Default: regular backspace
        else {
            FlipioApp.logger.debug("deleteTypedText: using regular backspace for \(bundleId)")
            simulateBackspace(count: count)
        }
    }
    
    private func simulateCopy() -> Bool {
        FlipioApp.logger.debug("simulateCopy: sending Cmd+C")
        return simulateKeyCombo(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
    }
    
    private func simulatePaste() -> Bool {
        FlipioApp.logger.debug("simulatePaste: sending Cmd+V")
        return simulateKeyCombo(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
    }

    
     private func simulateBackspace(count: Int) {
        guard count > 0 else { return }
        FlipioApp.logger.debug("simulateBackspace: sending \(count) × Backspace")
        
        let keyCode = CGKeyCode(kVK_Delete)
        
        for _ in 0..<count {
            guard
                let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
                let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
            else { 
                FlipioApp.logger.error("simulateBackspace: failed to create CGEvent")
                continue 
            }
            down.flags = []
            up.flags = []
            down.post(tap: .cghidEventTap)
            usleep(10_000)
            up.post(tap: .cghidEventTap)
            // usleep(30_000)
        }
    }

    private func simulateBackspace_v2(count: Int) {
        guard count > 0 else { return }
        FlipioApp.logger.debug("simulateBackspace_v2: sending \(count) × Control+Backspace")
        
        let keyCode = CGKeyCode(kVK_Delete)
        
        for _ in 0..<count {
            guard
                let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
                let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
            else { 
                FlipioApp.logger.error("simulateBackspace_v2: failed to create CGEvent")
                continue 
            }
            
            down.flags = .maskControl
            up.flags = .maskControl
            
            down.post(tap: .cghidEventTap)
            usleep(30_000)
//            up.post(tap: .cghidEventTap)
//            usleep(30_000)
        }
    }


    /// Selects text using Shift+Left Arrow, then deletes it.
    /// This method works reliably across all applications.
    private func simulateBackspaceViaSelection(count: Int) {
        guard count > 0 else { return }
        FlipioApp.logger.debug("simulateBackspaceViaSelection: selecting \(count) chars and deleting")
        
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            FlipioApp.logger.error("simulateBackspaceViaSelection: failed to create CGEventSource")
            return
        }
        
        let leftArrowCode = CGKeyCode(kVK_LeftArrow)
        let deleteCode = CGKeyCode(kVK_Delete)
        
        // Select text by pressing Shift+Left Arrow multiple times
        for _ in 0..<count {
            guard
                let down = CGEvent(keyboardEventSource: source, virtualKey: leftArrowCode, keyDown: true),
                let up = CGEvent(keyboardEventSource: source, virtualKey: leftArrowCode, keyDown: false)
            else {
                FlipioApp.logger.error("simulateBackspaceViaSelection: failed to create arrow events")
                continue
            }
            
            down.flags = .maskShift
            up.flags = .maskShift
            
            down.setIntegerValueField(.eventSourceUserData, value: FlipioSyntheticEventUserData)
            up.setIntegerValueField(.eventSourceUserData, value: FlipioSyntheticEventUserData)
            
            down.post(tap: .cgSessionEventTap)
            usleep(10_000)
            up.post(tap: .cgSessionEventTap)
        }
        
        // Now delete the selected text
        usleep(10_000)
        guard
            let deleteDown = CGEvent(keyboardEventSource: source, virtualKey: deleteCode, keyDown: true),
            let deleteUp = CGEvent(keyboardEventSource: source, virtualKey: deleteCode, keyDown: false)
        else {
            FlipioApp.logger.error("simulateBackspaceViaSelection: failed to create delete events")
            return
        }
        
        deleteDown.flags = []
        deleteUp.flags = []
        
        deleteDown.setIntegerValueField(.eventSourceUserData, value: FlipioSyntheticEventUserData)
        deleteUp.setIntegerValueField(.eventSourceUserData, value: FlipioSyntheticEventUserData)
        
        deleteDown.post(tap: .cgSessionEventTap)
        usleep(10_000)
        deleteUp.post(tap: .cgSessionEventTap)
    }
    
    private func simulateTyping(_ text: String) {
        guard !text.isEmpty else { return }
        FlipioApp.logger.debug("simulateTyping: typing \(text.count) characters")
        
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            FlipioApp.logger.error("simulateTyping: failed to create CGEventSource")
            return
        }
        
        for char in text {
            let utf16 = Array(String(char).utf16)
            
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                FlipioApp.logger.error("simulateTyping: failed to create key events")
                return
            }
            
            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            
            keyDown.setIntegerValueField(.eventSourceUserData, value: FlipioSyntheticEventUserData)
            keyUp.setIntegerValueField(.eventSourceUserData, value: FlipioSyntheticEventUserData)

            keyDown.flags = []
            keyUp.flags = []
            
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)
        }
    }
    
    /// Sends a synthetic key press (down+up) with the given modifiers to the session.
    private func simulateKeyCombo(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            FlipioApp.logger.error("simulateKeyCombo: failed to create CGEventSource")
            return false
        }
        
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            FlipioApp.logger.error("simulateKeyCombo: failed to create key events")
            return false
        }
        
        keyDown.flags = flags
        keyUp.flags = flags
        
        keyDown.setIntegerValueField(.eventSourceUserData, value: FlipioSyntheticEventUserData)
        keyUp.setIntegerValueField(.eventSourceUserData, value: FlipioSyntheticEventUserData)
        
        // Use cghidEventTap for more reliable delivery to the frontmost application
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        
        
        return true
    }
}
