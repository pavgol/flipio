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
                "Attempting typed-word conversion for \(word, privacy: .public)"
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
                "convertAndReplace: textBeforeCopy `\(textBeforeCopy ?? "", privacy: .public)`, originalText `\(originalText, privacy: .public)`")
        }
        
        guard let conversion = converter.convertWithTarget(originalText) else {
            FlipioApp.logger.warning("convertAndReplace: no keyboard layouts available")
            return false
        }
        let converted = conversion.text
        
        FlipioApp.logger.notice(
            "conversion: \(originalText, privacy: .public) → \(converted, privacy: .public) (clipboard)"
        )
        
        pasteboard.clearContents()
        pasteboard.setString(converted, forType: .string)
        
        let originalText2 = pasteboard.string(forType: .string)
        FlipioApp.logger.debug("convertAndReplace: clipboard has `\(originalText2 ?? "nil", privacy: .public)`")
        
        Thread.sleep(forTimeInterval: Self.clipboardOperationDelay)
        guard simulatePaste() else {
            FlipioApp.logger.error("convertAndReplace: failed to synthesize Cmd+V")
            return false
        }
        converter.applyTargetLayout(conversion.targetLayout)
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
            "replaceTypedWordWithNextLayout: \(original, privacy: .public) → \(replacement, privacy: .public)"
        )
        
        // Delete the original text using app-appropriate strategy
        deleteTypedText(count: original.count)

        // Type the replacement text character by character
        KeySimulator.postUnicodeString(replacement)

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
        
        FlipioApp.logger.debug("snapshotPasteboard: captured \(snapshot.count, privacy: .public) items")
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
            "restorePasteboard: restored \(itemsToWrite.count, privacy: .public) items (success=\(wrote, privacy: .public))")
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
            simulateBackspaceWithControl(count: count)
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
            simulateBackspaceWithControl(count: count)
        }
        // Default: regular backspace
        else {
            FlipioApp.logger.debug("deleteTypedText: using regular backspace for \(bundleId)")
            simulateBackspace(count: count)
        }
    }
    
    private func simulateCopy() -> Bool {
        FlipioApp.logger.debug("simulateCopy: sending Cmd+C")
        return KeySimulator.postKeyPress(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
    }
    
    private func simulatePaste() -> Bool {
        FlipioApp.logger.debug("simulatePaste: sending Cmd+V")
        return KeySimulator.postKeyPress(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
    }

    
     private func simulateBackspace(count: Int) {
        for _ in 0..<count {
            KeySimulator.postKeyPress(
                keyCode: CGKeyCode(kVK_Delete)
            )
        }
    }

    private func simulateBackspaceWithControl(count: Int) {
        for _ in 0..<count {
            KeySimulator.postKeyPress(
                keyCode: CGKeyCode(kVK_Delete),
                flags: .maskControl
                //BUG: potential bug here because initial implementation didn't trigger key up. Looks like no
            )
            usleep(10_000)
        }
    }


    /// Selects text using Shift+Left Arrow, then deletes it.
    /// This method works reliably across all applications.
    private func simulateBackspaceViaSelection(count: Int) {
        for _ in 0..<count {
            KeySimulator.postKeyPress(
                keyCode: CGKeyCode(kVK_LeftArrow),
                flags: .maskShift
            )
        }

        // Now delete the selected text
        usleep(10_000)
        KeySimulator.postKeyPress(
            keyCode: CGKeyCode(kVK_Delete)
        )
    }
}
