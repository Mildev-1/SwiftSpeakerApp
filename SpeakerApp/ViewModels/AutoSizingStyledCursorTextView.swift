import SwiftUI

#if os(iOS)
import UIKit

struct AutoSizingStyledCursorTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var isFocused: Bool

    let isEditable: Bool
    @Binding var resignFocusToken: Int
    @Binding var measuredHeight: CGFloat

    var disableContextMenu: Bool = true

    func makeUIView(context: Context) -> UITextView {
        let tv: UITextView = disableContextMenu ? LockedActionsTextView() : UITextView()

        tv.delegate = context.coordinator
        tv.isScrollEnabled = false

        tv.font = UIFont.systemFont(ofSize: 17)
        tv.backgroundColor = UIColor.orange
        tv.textColor = UIColor.black
        tv.tintColor = UIColor.black

        tv.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.widthTracksTextView = true
        tv.textContainer.lineBreakMode = .byWordWrapping

        tv.isEditable = isEditable
        tv.isSelectable = true

        // Kill input assistant bar
        tv.inputAssistantItem.leadingBarButtonGroups = []
        tv.inputAssistantItem.trailingBarButtonGroups = []

        // Reduce “smart” edits (optional)
        tv.autocorrectionType = .no
        tv.smartDashesType = .no
        tv.smartQuotesType = .no
        tv.smartInsertDeleteType = .no

        if #available(iOS 11.0, *) {
            tv.textDragInteraction?.isEnabled = false
        }

        // ✅ Critical: allow SwiftUI to constrain width (prevents runaway single-line width)
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Vertical: let SwiftUI control height; we measure and feed it back
        tv.setContentHuggingPriority(.defaultLow, for: .vertical)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        tv.text = text
        tv.selectedRange = selectedRange

        DispatchQueue.main.async {
            measuredHeight = Self.fittingHeight(for: tv)
        }

        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.isEditable = isEditable

        if uiView.text != text {
            uiView.text = text
        }

        if uiView.selectedRange.location != selectedRange.location || uiView.selectedRange.length != selectedRange.length {
            uiView.selectedRange = selectedRange
        }

        if context.coordinator.lastResignToken != resignFocusToken {
            context.coordinator.lastResignToken = resignFocusToken
            uiView.resignFirstResponder()
            isFocused = false
        }

        DispatchQueue.main.async {
            measuredHeight = Self.fittingHeight(for: uiView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Height

    private static func fittingHeight(for tv: UITextView) -> CGFloat {
        // Ensure layout has applied the correct width constraints
        tv.layoutIfNeeded()

        // Prefer current constrained width; if not ready yet, fall back to screen-safe width
        var width = tv.bounds.width
        if width <= 1 {
            width = tv.superview?.bounds.width ?? UIScreen.main.bounds.width
        }
        width = max(1, width)

        let target = CGSize(width: width, height: .greatestFiniteMagnitude)
        let h = tv.sizeThatFits(target).height

        return ceil(h)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: AutoSizingStyledCursorTextView
        var lastResignToken: Int

        init(_ parent: AutoSizingStyledCursorTextView) {
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

            DispatchQueue.main.async {
                self.parent.measuredHeight = AutoSizingStyledCursorTextView.fittingHeight(for: textView)
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // ✅ Collapse selection to caret only (no select/select-all highlighting)
            if parent.disableContextMenu, textView.selectedRange.length > 0 {
                let caret = NSRange(
                    location: textView.selectedRange.location + textView.selectedRange.length,
                    length: 0
                )
                textView.selectedRange = caret
            }
            parent.selectedRange = textView.selectedRange
        }
    }
}

// MARK: - Locked actions (no menu)

final class LockedActionsTextView: UITextView {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        false
    }

    override func copy(_ sender: Any?) {}
    override func cut(_ sender: Any?) {}
    override func paste(_ sender: Any?) {}
    override func select(_ sender: Any?) {}
    override func selectAll(_ sender: Any?) {}
    override func delete(_ sender: Any?) {}
}

#endif
