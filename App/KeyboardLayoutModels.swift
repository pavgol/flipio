//
//  Core models for keyboard layout conversion.
//

import Foundation

/// A pair of keyboard layouts with bidirectional character mapping.
struct KeyboardLayoutPair: Sendable {
    let id: String
    let nameA: KeyboardInputSourceInfo
    let nameB: KeyboardInputSourceInfo
    /// Map: character in layout A → character in layout B (lowercase).
    let aToB: [Character: Character]
    /// Map: character in layout B → character in layout A (lowercase).
    let bToA: [Character: Character]

    /// Convert text from layout A to B (preserving case).
    func convertAToB(_ text: String) -> String {
        convert(text, map: aToB)
    }

    /// Convert text from layout B to A (preserving case).
    func convertBToA(_ text: String) -> String {
        convert(text, map: bToA)
    }

    /// Convert text that may contain a mix of both layouts (preserving case).
    func convertMixed(_ text: String) -> String {
        return convertMixedWithTarget(text).text
    }

    /// Convert text that may contain a mix of both layouts and report the last target layout.
    func convertMixedWithTarget(_ text: String) -> ConversionResult {
        var result = ""
        result.reserveCapacity(text.count)
        var lastTarget: KeyboardInputSourceInfo = nameB

        for char in text {
            if let mapped = mapPreservingCase(char, map: aToB) {
                result.append(mapped)
                // Only count this as a direction signal when the character actually changed.
                // Digits and other layout-neutral characters map to themselves in both aToB and
                // bToA; letting them update lastTarget would flip the target to the wrong side.
                if mapped != char {
                    lastTarget = nameB
                }
                continue
            }
            if let mapped = mapPreservingCase(char, map: bToA) {
                result.append(mapped)
                if mapped != char {
                    lastTarget = nameA
                }
                continue
            }
            result.append(char)
        }
        return ConversionResult(text: result, targetLayout: lastTarget)
    }

    private func convert(_ text: String, map: [Character: Character]) -> String {
        var result = ""
        result.reserveCapacity(text.count)

        for char in text {
            if let mapped = mapPreservingCase(char, map: map) {
                result.append(mapped)
            } else {
                result.append(char)
            }
        }
        return result
    }

    private func mapPreservingCase(_ char: Character, map: [Character: Character]) -> Character? {
        if let mapped = map[char] { return mapped }
        if let lower = char.lowercased().first, let mapped = map[lower] {
            return Character(mapped.uppercased())
        }
        return nil
    }

    /// Heuristic: does this string look like it's in script A (e.g. Latin)?
    func seemsLikeLayoutA(_ text: String) -> Bool {
        let aChars = Set(aToB.keys)
        let matchCount = text.filter { aChars.contains($0) || aChars.contains(Character($0.lowercased())) }.count
        let total = text.filter { $0.isLetter }.count
        if total == 0 { return true }
        return Double(matchCount) / Double(total) >= 0.5
    }
}

/// Represents a selected pair of keyboard layouts with their source IDs.
struct KeyboardLayoutSelection: Sendable {
    let pair: KeyboardLayoutPair
    let sourceAID: String?
    let sourceBID: String?
}

/// Result of a text conversion operation.
struct ConversionResult: Sendable {
    let text: String
    let targetLayout: KeyboardInputSourceInfo
}
