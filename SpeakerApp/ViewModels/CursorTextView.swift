import SwiftUI
import UIKit

struct CursorTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var isFocused: Bool

    var isEditable: Bool
    @Binding var resignFocusToken: Int

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isScrollEnabled = true
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.backgroundColor = .clear
        tv.delegate = context.coordinator
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.isEditable = isEditable

        if uiView.text != text { uiView.text = text }

        if uiView.selectedRange.location != selectedRange.location || uiView.selectedRange.length != selectedRange.length {
            uiView.selectedRange = selectedRange
        }

        // ✅ Resign focus when token changes
        if context.coordinator.lastResignToken != resignFocusToken {
            context.coordinator.lastResignToken = resignFocusToken
            uiView.resignFirstResponder()
            isFocused = false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: CursorTextView
        var lastResignToken: Int = 0

        init(_ parent: CursorTextView) {
            self.parent = parent
            self.lastResignToken = parent.resignFocusToken
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
            parent.selectedRange = textView.selectedRange
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
            parent.selectedRange = textView.selectedRange
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            parent.selectedRange = textView.selectedRange
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.selectedRange = textView.selectedRange
        }
    }
}
