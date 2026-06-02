import SwiftUI
import UIKit

struct EditorTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var jumpTarget: JumpTarget?

    struct JumpTarget: Equatable {
        let line: Int
        let column: Int?
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = true
        tv.isSelectable = true
        tv.alwaysBounceVertical = true
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.font = UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        tv.text = text
        tv.delegate = context.coordinator
        tv.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.3)
        tv.layer.cornerRadius = 8
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text { uiView.text = text }
        if let target = jumpTarget {
            if let pos = positionFor(line: target.line, column: target.column, in: uiView.text) {
                let nsRange = NSRange(location: pos, length: 0)
                uiView.selectedRange = nsRange
                uiView.scrollRangeToVisible(nsRange)
            }
            // Clear jump target after handling
            DispatchQueue.main.async { self.jumpTarget = nil }
        }
    }

    private func positionFor(line: Int, column: Int?, in full: String) -> Int? {
        if line <= 0 { return 0 }
        let lines = full.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard line <= lines.count else { return full.count }
        var offset = 0
        for i in 0..<(line - 1) { offset += lines[i].count + 1 }
        let current = lines[line - 1]
        let col = max(0, min((column ?? 1) - 1, current.count))
        return offset + col
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: EditorTextView
        init(_ parent: EditorTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
    }
}

