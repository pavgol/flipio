//
//  System input source detection, keyboard layout pair building,
//  and input source switching (with system HUD support).
//

import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os

/// Information about a keyboard input source.
struct KeyboardInputSourceInfo {
    let id: String
    let name: String
    let primaryLanguage: String
    let source: TISInputSource
}

/// Provides access to system keyboard input sources.
struct SystemInputSourceProvider {

    /// Returns all selectable keyboard input sources with Unicode key layouts.
    func selectableSources() -> [KeyboardInputSourceInfo] {
        allSources().compactMap { makeSourceInfo(from: $0) }
    }

    /// Returns the ID of the currently active keyboard input source.
    func currentSourceID() -> String? {
        guard let current = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            return nil
        }
        return getStringProperty(current, key: kTISPropertyInputSourceID)
    }

    /// Returns a preferred pair of layouts based on system preferred languages.
    /// Uses the first two input sources that match the system's preferred languages.
    /// Falls back to the first two selectable sources if no language match is found.
    func selectPreferredPair() -> (
        primary: KeyboardInputSourceInfo, secondary: KeyboardInputSourceInfo
    )? {
        let sources = selectableSources()
        guard let fallbackPair = firstDistinctPair(in: sources) else { return nil }

        // Get system preferred languages
        let preferredLanguages = Locale.preferredLanguages
        guard preferredLanguages.count >= 2 else {
            return fallbackPair
        }

        // Try to match sources with preferred languages
        var matchedSources: [KeyboardInputSourceInfo] = []
        for language in preferredLanguages.prefix(2) {
            let languageCode = preferredLanguageCode(from: language)
            if let source = sources.first(where: { candidate in
                matchesLanguageCode(languageCode, source: candidate)
                    && !matchedSources.contains(where: { $0.id == candidate.id })
            }) {
                matchedSources.append(source)
            }
        }

        // If we found at least 2 matching sources, use them
        if matchedSources.count >= 2 {
            return (primary: matchedSources[0], secondary: matchedSources[1])
        }

        return fallbackPair
    }

    /// Returns the next layout in the cycle for live typing conversion.
    /// Cycles through all available layouts: A->B->C->A...
    func selectNextLayout(after currentID: String?) -> KeyboardInputSourceInfo? {
        let sources = selectableSources()
        return nextSource(after: currentID, in: sources)
    }

    /// Activates the input source with the given ID.
    /// Prefers the system-hotkey path (which shows the HUD) via `switchToNext()`, cycling
    /// up to `selectableSources().count` times until the desired source becomes current.
    /// Falls back to direct TISSelectInputSource if the hotkey never reaches the target.
    func activateInputSource(id target: KeyboardInputSourceInfo) {
        FlipioApp.logger.debug("activateInputSource: activating '\(target.id, privacy: .public)'")
        // No-op if already current.
        if currentSourceID() == target.id {
            FlipioApp.logger.debug("activateInputSource: '\(target.id, privacy: .public)' is already active")
            return
        }
        //TODO: now two system layouts are supported only.
        //it is a challenge to get the current system layout after switch done via hotkey
        //hotkey switch is preferred because it shows the HUD and when user returns back to the edit area then
        //the layout is restored
        switchToNextInputSource()
    }

    // MARK: - Cycling switch with system HUD

    // Symbolic hotkey IDs for input source switching (com.apple.symbolichotkeys):
    //   60 = "Select the previous input source"  (default: ⌃Space)
    //   61 = "Select next source in Input menu"  (default: ⌃⌥Space)
    // macOS versions differ on which ID gets ⌃Space; we try both.
    private static let hotkeyIDs = [60, 61]
    private static var lastSelectedIndex: Int?

    /// Switches to the next input source in the list.
    /// Prefers simulating the system shortcut (hotkey IDs 60/61) so the window server
    /// shows the layout-change HUD. Falls back to direct TISSelectInputSource when the
    /// shortcut cannot be read (e.g. sandbox blocks cfprefsd cross-app prefs access).
    func switchToNextInputSource() {
        for id in Self.hotkeyIDs {
            if let params = Self.readSystemHotkey(id: id) {
                FlipioApp.logger.info(
                    "switchToNextInputSource: CGEvent path via hotkey ID \(id, privacy: .public) — keyCode=\(params.keyCode, privacy: .public) modifiers=0x\(String(params.modifiers, radix: 16), privacy: .public)"
                )
                KeySimulator.postKeyPress(
                    keyCode: CGKeyCode(params.keyCode),
                    flags: Self.carbonModifiersToCGEventFlags(params.modifiers)
                )
                return
            }
        }
        FlipioApp.logger.warning(
            "switchToNext: no enabled hotkey found for IDs \(Self.hotkeyIDs, privacy: .public) — falling back to direct TISSelectInputSource (no HUD)"
        )
        switchToNextViaTIS()
    }

    /// Converts Carbon-style modifier mask (as stored in com.apple.symbolichotkeys) to CGEventFlags.
    private static func carbonModifiersToCGEventFlags(_ carbonMods: Int) -> CGEventFlags {
        var flags: CGEventFlags = []
        if carbonMods & 0x02_0000 != 0 { flags.insert(.maskShift) }
        if carbonMods & 0x04_0000 != 0 { flags.insert(.maskControl) }
        if carbonMods & 0x08_0000 != 0 { flags.insert(.maskAlternate) }
        if carbonMods & 0x10_0000 != 0 { flags.insert(.maskCommand) }
        return flags
    }

    private struct HotkeyParams {
        let keyCode: Int
        let modifiers: Int
    }

    /// Reads the configured shortcut for a symbolic hotkey ID from
    /// com.apple.symbolichotkeys preferences (via cfprefsd).
    /// Requires the `com.apple.security.temporary-exception.shared-preference.read-only`
    /// sandbox entitlement for `com.apple.symbolichotkeys`.
    private static func readSystemHotkey(id: Int) -> HotkeyParams? {
        guard
            let raw = CFPreferencesCopyAppValue(
                "AppleSymbolicHotKeys" as CFString,
                "com.apple.symbolichotkeys" as CFString
            ) as? [String: Any]
        else {
            FlipioApp.logger.warning(
                "readSystemHotkey(\(id, privacy: .public)): could not read com.apple.symbolichotkeys (sandbox may block cross-app prefs)"
            )
            return nil
        }
        guard let entry = raw[String(id)] as? [String: Any] else {
            let enabledIDs = raw.compactMap { k, v -> String? in
                guard let d = v as? [String: Any], (d["enabled"] as? Bool) == true else {
                    return nil
                }
                return k
            }.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
            FlipioApp.logger.warning(
                "readSystemHotkey(\(id, privacy: .public)): ID \(id, privacy: .public) not present — enabled hotkey IDs in prefs: \(enabledIDs, privacy: .public)"
            )
            return nil
        }
        guard let enabled = entry["enabled"] as? Bool, enabled else {
            FlipioApp.logger.info(
                "readSystemHotkey(\(id, privacy: .public)): hotkey \(id, privacy: .public) exists but is disabled — entry: \(entry, privacy: .public)")
            return nil
        }
        guard
            let value = entry["value"] as? [String: Any],
            let parameters = value["parameters"] as? [Any],
            parameters.count >= 3,
            let keyCode = parameters[1] as? Int,
            let modifiers = parameters[2] as? Int
        else {
            FlipioApp.logger.warning(
                "readSystemHotkey(\(id, privacy: .public)): unexpected parameters structure: \(entry, privacy: .public)")
            return nil
        }
        FlipioApp.logger.debug(
            "readSystemHotkey(\(id, privacy: .public)): found keyCode=\(keyCode, privacy: .public) modifiers=0x\(String(modifiers, radix: 16), privacy: .public)"
        )
        return HotkeyParams(keyCode: keyCode, modifiers: modifiers)
    }

    // MARK: TIS fallback path

    private func switchToNextViaTIS() {
        let inputSourceList = allSources().filter { isSelectable($0) }
        FlipioApp.logger.debug(
            "switchToNextViaTIS: \(inputSourceList.count, privacy: .public) selectable sources found")
        guard !inputSourceList.isEmpty else {
            FlipioApp.logger.warning("switchToNextViaTIS: no selectable input sources")
            return
        }

        let nextIndex: Int
        if let last = Self.lastSelectedIndex {
            nextIndex = (last + 1) % inputSourceList.count
            FlipioApp.logger.debug(
                "switchToNextViaTIS: advancing from cached index \(last, privacy: .public) → \(nextIndex, privacy: .public)")
        } else {
            if let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
                let currentIndex = inputSourceList.firstIndex(where: { $0 == currentSource })
            {
                nextIndex = (currentIndex + 1) % inputSourceList.count
                FlipioApp.logger.debug(
                    "switchToNextViaTIS: first call, current index \(currentIndex, privacy: .public) → \(nextIndex, privacy: .public)")
            } else {
                nextIndex = 0
                FlipioApp.logger.debug(
                    "switchToNextViaTIS: first call, current source not in list, defaulting to index 0"
                )
            }
        }
        let result = TISSelectInputSource(inputSourceList[nextIndex])
        if result == noErr {
            FlipioApp.logger.info(
                "switchToNextViaTIS: switched to index \(nextIndex, privacy: .public) (OSStatus=\(result, privacy: .public))")
        } else {
            FlipioApp.logger.error(
                "switchToNextViaTIS: TISSelectInputSource failed OSStatus=\(result, privacy: .public))")
        }
        Self.lastSelectedIndex = nextIndex
    }

    private func isSelectable(_ source: TISInputSource) -> Bool {
        guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable)
        else {
            return false
        }
        return Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue() == kCFBooleanTrue
    }

    private func hasUnicodeKeyLayout(_ source: TISInputSource) -> Bool {
        return TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) != nil
    }

    private func allSources() -> [TISInputSource] {
        guard
            let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue()
                as? [TISInputSource]
        else {
            return []
        }
        return list
    }

    private func makeSourceInfo(from source: TISInputSource) -> KeyboardInputSourceInfo? {
        guard isSelectable(source), hasUnicodeKeyLayout(source) else { return nil }

        let id = getStringProperty(source, key: kTISPropertyInputSourceID) ?? "unknown"
        let name = getStringProperty(source, key: kTISPropertyLocalizedName) ?? id
        let primaryLanguage = getPrimaryLanguageProperty(
            source, key: kTISPropertyInputSourceLanguages)

        return KeyboardInputSourceInfo(
            id: id, name: name, primaryLanguage: primaryLanguage, source: source)
    }

    private func source(withID targetID: String) -> TISInputSource? {
        allSources().first { getStringProperty($0, key: kTISPropertyInputSourceID) == targetID }
    }

    private func firstDistinctPair(in sources: [KeyboardInputSourceInfo]) -> (
        primary: KeyboardInputSourceInfo, secondary: KeyboardInputSourceInfo
    )? {
        guard let primary = sources.first,
            let secondary = sources.first(where: { $0.id != primary.id })
        else {
            return nil
        }
        return (primary: primary, secondary: secondary)
    }

    private func nextSource(
        after currentID: String?,
        in sources: [KeyboardInputSourceInfo]
    ) -> KeyboardInputSourceInfo? {
        guard !sources.isEmpty else { return nil }
        guard let currentID,
            let currentIndex = sources.firstIndex(where: { $0.id == currentID })
        else {
            return sources.first
        }

        let nextIndex = (currentIndex + 1) % sources.count
        return sources[nextIndex]
    }

    private func matchesLanguageCode(_ languageCode: String, source: KeyboardInputSourceInfo)
        -> Bool
    {
        guard !source.primaryLanguage.isEmpty else {
            return false
        }
        return source.primaryLanguage.caseInsensitiveCompare(languageCode) == .orderedSame
    }

    private func preferredLanguageCode(from identifier: String) -> String {
        let locale = Locale(identifier: identifier)
        if let languageCode = locale.language.languageCode?.identifier {
            return languageCode
        }

        return identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)
            ?? identifier
    }

    private func getStringProperty(_ source: TISInputSource, key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        let value = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue()
        return value as String
    }

    private func getPrimaryLanguageProperty(_ source: TISInputSource, key: CFString) -> String {
        guard let raw = TISGetInputSourceProperty(source, key) else { return "" }
        let value = Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue()
        let languages = value as? [String] ?? []
        return languages.first ?? ""
    }
}

/// Builds keyboard layout pairs from system input sources.
enum KeyboardLayoutPairBuilder {

    /// Builds a selection with pair and source IDs from two input sources.
    static func buildSelection(
        from primary: KeyboardInputSourceInfo,
        and secondary: KeyboardInputSourceInfo
    ) -> KeyboardLayoutSelection {
        let mapping = buildMapping(from: primary, to: secondary)
        let pair = KeyboardLayoutPair(
            id: "\(primary.id)-\(secondary.id)",
            nameA: primary,
            nameB: secondary,
            aToB: mapping.aToB,
            bToA: mapping.bToA
        )
        return KeyboardLayoutSelection(
            pair: pair,
            sourceAID: primary.id,
            sourceBID: secondary.id
        )
    }

    private static func buildMapping(
        from sourceA: KeyboardInputSourceInfo,
        to sourceB: KeyboardInputSourceInfo
    ) -> (aToB: [Character: Character], bToA: [Character: Character]) {
        var aToB: [Character: Character] = [:]
        var bToA: [Character: Character] = [:]

        let modifiers: [UInt32] = [0, UInt32(shiftKey)]

        for keyCode in UInt16(0)..<UInt16(128) {
            for modifier in modifiers {
                guard
                    let aChar = translateCharacter(
                        keyCode: keyCode, modifiers: modifier, source: sourceA),
                    let bChar = translateCharacter(
                        keyCode: keyCode, modifiers: modifier, source: sourceB)
                else { continue }

                if aToB[aChar] == nil { aToB[aChar] = bChar }
                if bToA[bChar] == nil { bToA[bChar] = aChar }
            }
        }

        return (aToB: aToB, bToA: bToA)
    }

    /// Builds a one-way character mapping from source A to source B.
    static func buildOneWayMapping(
        from sourceA: KeyboardInputSourceInfo,
        to sourceB: KeyboardInputSourceInfo
    ) -> [Character: Character] {
        let mapping = buildMapping(from: sourceA, to: sourceB)
        return mapping.aToB
    }

    private static func translateCharacter(
        keyCode: UInt16,
        modifiers: UInt32,
        source: KeyboardInputSourceInfo
    ) -> Character? {
        guard
            let layoutData = TISGetInputSourceProperty(
                source.source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }

        let data = unsafeBitCast(layoutData, to: CFData.self)
        guard let ptr = CFDataGetBytePtr(data) else { return nil }
        let keyboardLayout = UnsafeRawPointer(ptr).assumingMemoryBound(to: UCKeyboardLayout.self)

        var deadKeyState: UInt32 = 0
        var chars: [UniChar] = Array(repeating: 0, count: 8)
        var length: Int = 0
        let modifierState = modifiers >> 8

        let status = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDown),
            modifierState,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )

        guard status == noErr, length > 0 else { return nil }

        let string = String(utf16CodeUnits: chars, count: length)
        guard string.count == 1, let char = string.first else { return nil }

        if char.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) {
            return nil
        }
        return char
    }
}
