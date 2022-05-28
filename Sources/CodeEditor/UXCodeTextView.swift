//
//  UXCodeTextView.swift
//  CodeEditor
//
//  Created by Helge Heß.
//  Copyright © 2021 ZeeZide GmbH. All rights reserved.
//

import Highlightr
import SwiftUI

#if os(macOS)
    import AppKit

    typealias UXTextView = NSTextView
    typealias UXTextViewDelegate = NSTextViewDelegate
#else
    import UIKit

    typealias UXTextView = UITextView
    typealias UXTextViewDelegate = UITextViewDelegate
#endif

// MARK: - UXCodeTextView

/**
 * Subclass of NSTextView/UITextView which adds some code editing features to
 * the respective Cocoa views.
 *
 * Currently pretty tightly coupled to `CodeEditor`.
 */
final class UXCodeTextView: UXTextView {
    // MARK: Lifecycle

    init() {
        let textStorage = highlightr.flatMap {
            CodeAttributedString(highlightr: $0)
        }
            ?? NSTextStorage()

        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true // those are key!
        layoutManager.addTextContainer(textContainer)

        super.init(frame: .zero, textContainer: textContainer)

        #if os(macOS)
            isVerticallyResizable = true
            maxSize = .init(width: 0, height: 1_000_000)

            isRichText = false
            allowsImageEditing = false
            isGrammarCheckingEnabled = false
            isContinuousSpellCheckingEnabled = false
            isAutomaticSpellingCorrectionEnabled = false
            isAutomaticLinkDetectionEnabled = false
            isAutomaticDashSubstitutionEnabled = false
            isAutomaticQuoteSubstitutionEnabled = false
            usesRuler = false
        #else
            autocapitalizationType = .none
            autocorrectionType = .no
            smartDashesType = .no
            smartQuotesType = .no
            smartInsertDeleteType = .no
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    #if os(macOS)
        override var backgroundColor: NSColor { get { .clear } set {} }
        override var drawsBackground: Bool { get { false } set {} }
    #endif
    /// If the user starts a newline, the editor automagically adds the same
    /// whitespace as on the previous line.
    var isSmartIndentEnabled = true

    var autoPairCompletion = [String: String]()

    var indentStyle = CodeEditor.IndentStyle.system {
        didSet {
            guard oldValue != indentStyle else { return }
            reindent(oldStyle: oldValue)
        }
    }

    var language: CodeEditor.Language? {
        set {
            guard hlTextStorage?.language != newValue?.rawValue else { return }
            hlTextStorage?.language = newValue?.rawValue
        }
        get { hlTextStorage?.language.flatMap(CodeEditor.Language.init) }
    }

    private(set) var themeName = CodeEditor.ThemeName.default {
        didSet {
            highlightr?.setTheme(to: themeName.rawValue)
            if let bg = highlightr?.theme.themeBackgroundColor, let coordinator = delegate as? UXCodeTextViewDelegate {
                coordinator.backgroundColor = Color(bg.cgColor)
            }
            if let font = highlightr?.theme?.codeFont, font.familyName == "Courier" {
                highlightr?.theme?.setCodeFont(.monospacedSystemFont(ofSize: font.pointSize, weight: .medium))
            }
            if let font = highlightr?.theme?.codeFont { self.font = font }
        }
    }

    // MARK: - Actions

    #if os(macOS)
        override func changeFont(_ sender: Any?) {
            let coordinator = delegate as? UXCodeTextViewDelegate

            let old = coordinator?.fontSize
                ?? highlightr?.theme?.codeFont?.pointSize
                ?? NSFont.systemFontSize
            let new: CGFloat

            let fm = NSFontManager.shared
            switch fm.currentFontAction {
            case .sizeUpFontAction: new = old + 1
            case .sizeDownFontAction: new = old - 1

            case .viaPanelFontAction:
                guard let font = fm.selectedFont else {
                    return super.changeFont(sender)
                }
                new = font.pointSize

            case .addTraitFontAction, .removeTraitFontAction: // bold/italic
                NSSound.beep()
                return

            default:
                guard let font = fm.selectedFont else {
                    return super.changeFont(sender)
                }
                new = font.pointSize
            }

            coordinator?.fontSize = new
            applyNewFontSize(new)
        }
    #endif // macOS

    override func copy(_ sender: Any?) {
        guard let coordinator = delegate as? UXCodeTextViewDelegate else {
            assertionFailure("Expected coordinator as delegate")
            return super.copy(sender)
        }
        if coordinator.allowCopy { super.copy(sender) }
    }

    // MARK: - Themes

    @discardableResult
    func applyNewFontSize(_ newSize: CGFloat) -> Bool {
        applyNewTheme(nil, andFontSize: newSize)
    }

    @discardableResult
    func applyNewTheme(_ newTheme: CodeEditor.ThemeName) -> Bool {
        guard themeName != newTheme else { return false }
        guard let highlightr = highlightr,
              highlightr.setTheme(to: newTheme.rawValue),
              let theme = highlightr.theme else { return false }

        if let bg = theme.themeBackgroundColor, let coordinator = delegate as? UXCodeTextViewDelegate {
            coordinator.backgroundColor = Color(bg.cgColor)
        }
        if theme.codeFont.familyName == "Courier" {
            theme.setCodeFont(.monospacedSystemFont(ofSize: theme.codeFont.pointSize, weight: .medium))
        }
        if let font = theme.codeFont, font !== self.font { self.font = font }
        return true
    }

    @discardableResult
    func applyNewTheme(
        _ newTheme: CodeEditor.ThemeName? = nil,
        andFontSize newSize: CGFloat
    ) -> Bool {
        // Setting the theme reloads it (i.e. makes a "copy").
        guard let highlightr = highlightr,
              highlightr.setTheme(to: (newTheme ?? themeName).rawValue),
              let theme = highlightr.theme else { return false }

        if let bg = theme.themeBackgroundColor, let coordinator = delegate as? UXCodeTextViewDelegate {
            coordinator.backgroundColor = Color(bg.cgColor)
        }
        guard theme.codeFont?.pointSize != newSize else { return true }

        theme.codeFont = theme.codeFont?.withSize(newSize)
        theme.boldCodeFont = theme.boldCodeFont?.withSize(newSize)
        theme.italicCodeFont = theme.italicCodeFont?.withSize(newSize)
        if theme.codeFont.familyName == "Courier" {
            theme.setCodeFont(.monospacedSystemFont(ofSize: newSize, weight: .medium))
        }
        if let font = theme.codeFont, font !== self.font { self.font = font }
        return true
    }

    // MARK: Fileprivate

    fileprivate let highlightr = Highlightr()

    // MARK: Private

    private var hlTextStorage: CodeAttributedString? {
        textStorage as? CodeAttributedString
    }

    #if os(macOS)

        // MARK: - Smarts as shown in https://github.com/naoty/NTYSmartTextView

        private var isAutoPairEnabled: Bool { !autoPairCompletion.isEmpty }

        override func insertNewline(_ sender: Any?) {
            guard isSmartIndentEnabled else { return super.insertNewline(sender) }

            let currentLine = currentLine
            let wsPrefix = currentLine.prefix(while: {
                guard let scalar = $0.unicodeScalars.first else { return false }
                return CharacterSet.whitespaces.contains(scalar) // yes, yes
            })

            super.insertNewline(sender)

            if !wsPrefix.isEmpty {
                insertText(String(wsPrefix), replacementRange: selectedRange())
            }
        }

        override func insertTab(_ sender: Any?) {
            guard case let .softTab(width) = indentStyle else {
                return super.insertTab(sender)
            }
            super.insertText(
                String(repeating: " ", count: width),
                replacementRange: selectedRange()
            )
        }

        override func insertText(_ string: Any, replacementRange: NSRange) {
            super.insertText(string, replacementRange: replacementRange)
            guard isAutoPairEnabled else { return }
            guard let string = string as? String else { return } // TBD: NSAttrString

            guard let end = autoPairCompletion[string] else { return }
            super.insertText(end, replacementRange: selectedRange())
            super.moveBackward(self)
        }

        override func deleteBackward(_ sender: Any?) {
            guard isAutoPairEnabled, !isStartOrEndOfLine else {
                return super.deleteBackward(sender)
            }

            let s = string
            let selectedRange = swiftSelectedRange
            guard selectedRange.lowerBound > s.startIndex,
                  selectedRange.lowerBound < s.endIndex
            else {
                return super.deleteBackward(sender)
            }

            let startIdx = s.index(before: selectedRange.lowerBound)
            let startChar = s[startIdx ..< selectedRange.lowerBound]
            guard let expectedEndChar = autoPairCompletion[String(startChar)] else {
                return super.deleteBackward(sender)
            }

            let endIdx = s.index(after: selectedRange.lowerBound)
            let endChar = s[selectedRange.lowerBound ..< endIdx]
            guard expectedEndChar[...] == endChar else {
                return super.deleteBackward(sender)
            }

            super.deleteForward(sender)
            super.deleteBackward(sender)
        }
    #endif // macOS

    private func reindent(oldStyle: CodeEditor.IndentStyle) {
        // - walk over the lines, strip and count the whitespaces and do something
        //   clever :-)
    }
}

// MARK: - UXCodeTextViewDelegate

protocol UXCodeTextViewDelegate: UXTextViewDelegate {
    var allowCopy: Bool { get }
    var fontSize: CGFloat? { get set }
    var backgroundColor: Color? { get set }
}

// MARK: - Smarts as shown in https://github.com/naoty/NTYSmartTextView

extension UXTextView {
    var swiftSelectedRange: Range<String.Index> {
        let s = string
        guard !s.isEmpty else { return s.startIndex ..< s.startIndex }
        #if os(macOS)
            guard let selectedRange = Range(selectedRange(), in: s) else {
                assertionFailure("Could not convert the selectedRange?")
                return s.startIndex ..< s.startIndex
            }
        #else
            guard let selectedRange = Range(self.selectedRange, in: s) else {
                assertionFailure("Could not convert the selectedRange?")
                return s.startIndex ..< s.startIndex
            }
        #endif
        return selectedRange
    }

    fileprivate var currentLine: String {
        let s = string
        return String(s[s.lineRange(for: swiftSelectedRange)])
    }

    private var isEndOfLine: Bool {
        let (_, isEnd) = getStartOrEndOfLine()
        return isEnd
    }

    fileprivate var isStartOrEndOfLine: Bool {
        let (isStart, isEnd) = getStartOrEndOfLine()
        return isStart || isEnd
    }

    private func getStartOrEndOfLine() -> (isStart: Bool, isEnd: Bool) {
        let s = string
        let selectedRange = swiftSelectedRange
        var lineStart = s.startIndex, lineEnd = s.endIndex, contentEnd = s.endIndex
        string.getLineStart(
            &lineStart,
            end: &lineEnd,
            contentsEnd: &contentEnd,
            for: selectedRange
        )
        return (
            isStart: selectedRange.lowerBound == lineStart,
            isEnd: selectedRange.lowerBound == lineEnd
        )
    }
}

// MARK: - UXKit

#if os(macOS)

    extension NSTextView {
        var codeTextStorage: NSTextStorage? { textStorage }
    }
#else // iOS
    extension UITextView {
        var string: String { // NeXTstep was right!
            set { text = newValue }
            get { text }
        }

        var codeTextStorage: NSTextStorage? { textStorage }
    }
#endif // iOS
