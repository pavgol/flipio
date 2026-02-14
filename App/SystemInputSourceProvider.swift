//
//  SystemInputSourceProvider.swift
//  Flipio
//
//  System input source detection and keyboard layout pair building.
//

import Foundation
import Carbon.HIToolbox
import os

/// Information about a keyboard input source.
struct KeyboardInputSourceInfo {
    let id: String
    let name: String
    let source: TISInputSource
}

/// Provides access to system keyboard input sources.
struct SystemInputSourceProvider {
    
    /// Returns all selectable keyboard input sources with Unicode key layouts.
    func selectableSources() -> [KeyboardInputSourceInfo] {
        let options: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true
        ]

        guard let list = TISCreateInputSourceList(options as CFDictionary, false)?.takeRetainedValue() else {
            return []
        }

        let sources = (list as NSArray).map { $0 as! TISInputSource }.compactMap { source -> KeyboardInputSourceInfo? in
            guard hasUnicodeKeyLayout(source) else { return nil }

            let id = getStringProperty(source, key: kTISPropertyInputSourceID) ?? "unknown"
            let name = getStringProperty(source, key: kTISPropertyLocalizedName) ?? id

            return KeyboardInputSourceInfo(id: id, name: name, source: source)
        }
        return sources
    }

    /// Returns the ID of the currently active keyboard input source.
    func currentSourceID() -> String? {
        guard let current = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            return nil
        }
        return getStringProperty(current, key: kTISPropertyInputSourceID)
    }

    /// Selects a primary and secondary keyboard input source for layout conversion.
    /// Returns nil if fewer than 2 sources are available.
    func selectPair() -> (primary: KeyboardInputSourceInfo, secondary: KeyboardInputSourceInfo)? {
        let sources = selectableSources()
        guard sources.count >= 2 else { return nil }

        let currentID = currentSourceID()
        let primary = sources.first { $0.id == currentID } ?? sources[0]
        let secondary = sources.first { $0.id != primary.id } ?? sources[1]
        return (primary: primary, secondary: secondary)
    }
    
    /// Activates the input source with the given ID.
    func activateInputSource(id: String) {
        let options: [String: Any] = [kTISPropertyInputSourceID as String: id]
        guard let list = TISCreateInputSourceList(options as CFDictionary, false)?.takeRetainedValue() else {
            FlipioApp.logger.warning("Failed to find input source with id '\(id, privacy: .public)'")
            return
        }
        guard let first = (list as NSArray).firstObject else {
            FlipioApp.logger.warning("Input source list empty for id '\(id, privacy: .public)'")
            return
        }
        let source = first as! TISInputSource
        let result = TISSelectInputSource(source)
        
        if result == noErr {
            let name = getStringProperty(source, key: kTISPropertyLocalizedName) ?? id
            FlipioApp.logger.info("Switched to input source '\(name, privacy: .public)' (\(id, privacy: .public))")
        } else {
            FlipioApp.logger.error("Failed to activate input source '\(id, privacy: .public)' (error: \(result))")
        }
    }

    private func hasUnicodeKeyLayout(_ source: TISInputSource) -> Bool {
        return TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) != nil
    }

    private func getStringProperty(_ source: TISInputSource, key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        let value = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue()
        return value as String
    }
}

/// Builds keyboard layout pairs from system input sources.
enum KeyboardLayoutPairBuilder {
    
    /// Builds a selection with pair and source IDs from two input sources.
    static func buildSelection(
        from primary: KeyboardInputSourceInfo,
        and secondary: KeyboardInputSourceInfo
    ) -> KeyboardLayoutSelection {
        let mapping = buildMapping(from: primary.source, to: secondary.source)
        let pair = KeyboardLayoutPair(
            id: "\(primary.id)-\(secondary.id)",
            nameA: primary.name,
            nameB: secondary.name,
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
        from sourceA: TISInputSource,
        to sourceB: TISInputSource
    ) -> (aToB: [Character: Character], bToA: [Character: Character]) {
        var aToB: [Character: Character] = [:]
        var bToA: [Character: Character] = [:]

        let modifiers: [UInt32] = [0, UInt32(shiftKey)]

        for keyCode in UInt16(0)..<UInt16(128) {
            for modifier in modifiers {
                guard let aChar = translateCharacter(keyCode: keyCode, modifiers: modifier, source: sourceA),
                      let bChar = translateCharacter(keyCode: keyCode, modifiers: modifier, source: sourceB)
                else { continue }

                if aToB[aChar] == nil { aToB[aChar] = bChar }
                if bToA[bChar] == nil { bToA[bChar] = aChar }
            }
        }

        return (aToB: aToB, bToA: bToA)
    }

    private static func translateCharacter(
        keyCode: UInt16,
        modifiers: UInt32,
        source: TISInputSource
    ) -> Character? {
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
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
