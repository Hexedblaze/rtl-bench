import AppKit
import SwiftUI

private let editorInk = NSColor(srgbRed: 0.86, green: 0.90, blue: 0.94, alpha: 1)
private let editorBG = NSColor(srgbRed: 0.078, green: 0.105, blue: 0.14, alpha: 1)

private class CodeText: NSTextView {
    override func insertTab(_ sender: Any?) { insertText("    ", replacementRange: selectedRange()) }
}

struct CodeEditor: NSViewRepresentable {
    @Binding var source: String
    let isVHDL: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = editorBG
        let text = CodeText(frame: .zero)
        text.isRichText = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.isContinuousSpellCheckingEnabled = false
        text.isGrammarCheckingEnabled = false
        text.allowsUndo = true
        text.usesFindBar = true
        text.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        text.insertionPointColor = .white
        text.textColor = editorInk
        text.backgroundColor = editorBG
        text.textContainerInset = NSSize(width: 19, height: 16)
        text.isHorizontallyResizable = true
        text.isVerticallyResizable = true
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = false
        text.textContainer?.containerSize = text.maxSize
        text.autoresizingMask = [.width]
        text.delegate = context.coordinator
        scroll.documentView = text
        return scroll
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let text = view.documentView as? NSTextView, text.string != source else { return }
        text.string = source
        context.coordinator.colorize(text)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        init(_ parent: CodeEditor) { self.parent = parent }
        private let keywords = #"\b(?:module|endmodule|input|output|parameter|assign|reg|logic|wire|bit|always|always_ff|always_comb|posedge|negedge|begin|end|if|else|case|endcase|initial|integer|for|localparam|library|use|entity|is|port|in|out|architecture|of|signal|process|then|loop|wait|until|after|assert|report|severity|std_logic|unsigned|rising_edge)\b"#
        private lazy var verilog = expression(comments: #"//[^\n]*|/\*[\s\S]*?\*/"#, insensitive: false)
        private lazy var vhdl = expression(comments: #"--[^\n]*"#, insensitive: true)
        private func expression(comments: String, insensitive: Bool) -> NSRegularExpression {
            let pattern = "(" + comments + #")|("(?:\\.|[^"\n])*")|("# + keywords + #")|(\b[0-9]+(?:'[sS]?[bBoOdDhH][\w?]+)?\b)"#
            return try! NSRegularExpression(pattern: pattern, options: insensitive ? [.caseInsensitive] : [])
        }
        func textDidChange(_ notification: Notification) {
            guard let text = notification.object as? NSTextView else { return }
            parent.source = text.string
            colorize(text)
        }
        func colorize(_ text: NSTextView) {
            guard let layout = text.layoutManager else { return }
            let range = NSRange(location: 0, length: (text.string as NSString).length)
            layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
            guard range.length < 180_000 else { return }
            let colors = [NSColor.systemGray, NSColor.systemGreen, NSColor.systemTeal, NSColor.systemOrange]
            let regex = parent.isVHDL ? vhdl : verilog
            regex.enumerateMatches(in: text.string, range: range) { match, _, _ in
                guard let match else { return }
                for i in colors.indices where match.range(at: i + 1).location != NSNotFound {
                    layout.addTemporaryAttribute(.foregroundColor, value: colors[i], forCharacterRange: match.range)
                }
            }
        }
    }
}
