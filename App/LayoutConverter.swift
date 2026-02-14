//
//  LayoutConverter.swift
//  Flipio
//
//  Converts text between keyboard layouts.
//

import Foundation

/// Converts text between two keyboard layouts.
struct LayoutConverter: Sendable {
    private let layoutProvider: LayoutProvider

    init(layoutProvider: LayoutProvider = .init()) {
        self.layoutProvider = layoutProvider
    }

    /// Converts text to the other layout (e.g. "htgf" → "репа", "репа" → "htgf").
    /// Returns unchanged text if no keyboard layouts are available.
    func convert(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        
        guard let selection = layoutProvider.preferredSelection() else {
            return text
        }
        return selection.pair.convertMixed(text)
    }

    /// Converts text and returns detailed conversion result including target layout.
    /// Returns unchanged text if no keyboard layouts are available.
    func convertWithTarget(_ text: String) -> ConversionResult? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let selection = layoutProvider.preferredSelection() else {
            return nil
        }
        
        let conversion = selection.pair.convertMixedWithTarget(text)
        return ConversionResult(
            text: conversion.text,
            targetLayout: conversion.targetLayout,
            selection: selection
        )
    }

    /// Switches the system input source to the target layout from the conversion result.
    func applyTargetLayout(_ result: ConversionResult?) {
        guard let result else { return }
        layoutProvider.activateLayout(result.targetLayout, selection: result.selection)
    }
}

/// Provides keyboard layout selections and manages input source activation.
struct LayoutProvider: Sendable {
    private let inputSourceProvider = SystemInputSourceProvider()
    
    /// Returns the preferred keyboard layout selection from system input sources.
    /// Returns nil if fewer than 2 input sources are available.
    func preferredSelection() -> KeyboardLayoutSelection? {
        guard let pair = inputSourceProvider.selectPair() else {
            return nil
        }
        return KeyboardLayoutPairBuilder.buildSelection(from: pair.primary, and: pair.secondary)
    }

    /// Activates the specified layout side as the system input source.
    func activateLayout(_ target: KeyboardLayoutSide?, selection: KeyboardLayoutSelection) {
        guard let target else { return }
        
        let sourceID: String?
        switch target {
        case .layoutA:
            sourceID = selection.sourceAID
        case .layoutB:
            sourceID = selection.sourceBID
        }
        
        guard let sourceID else { return }
        inputSourceProvider.activateInputSource(id: sourceID)
    }
}
