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

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isScrollEnabled = false

        tv.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.widthTracksTextView = true
        tv.textContainer.lineBreakMode = .byWordWrapping

        tv.font = UIFont.systemFont(ofSize: 17)
        tv.backgroundColor = UIColor.orange
        tv.textColor = UIColor.black
        tv.tintColor = UIColor.black

        tv.delegate = context.coordinator
        tv.isEditable = isEditable
        tv.isSelectable = true

        // ✅ Important: ensure SwiftUI can constrain width (prevents overflow)
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        uiView.isEditable = isEditable
        uiView.backgroundColor = UIColor.orange
        uiView.textColor = UIColor.black
        uiView.tintColor = UIColor.black

        // Keep selection in sync
        let nsLen = (uiView.text as NSString).length
        let clampedLoc = max(0, min(selectedRange.location, nsLen))
        let clampedLen = max(0, min(selectedRange.length, nsLen - clampedLoc))
        let safe = NSRange(location: clampedLoc, length: clampedLen)

        if let start = uiView.position(from: uiView.beginningOfDocument, offset: safe.location),
           let end = uiView.position(from: start, offset: safe.length),
           let tr = uiView.textRange(from: start, to: end),
           uiView.selectedTextRange != tr {
            uiView.selectedTextRange = tr
        }

        // Focus handling
        if isFocused && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFocused && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }

        // Resign request (token bump)
        if context.coordinator.lastResignToken != resignFocusToken {
            context.coordinator.lastResignToken = resignFocusToken
            uiView.resignFirstResponder()
            isFocused = false
        }

        // ✅ Measure height ONLY when we have a real width (avoid UIScreen fallback!)
        DispatchQueue.main.async {
            let w = uiView.bounds.width
            guard w > 10 else { return } // wait until laid out inside the sheet

            let size = uiView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude))
            if abs(measuredHeight - size.height) > 0.5 {
                measuredHeight = size.height
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AutoSizingStyledCursorTextView
        var lastResignToken: Int = 0

        init(_ parent: AutoSizingStyledCursorTextView) {
            self.parent = parent
            self.lastResignToken = parent.resignFocusToken
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            let w = textView.bounds.width
            guard w > 10 else { return }
            let size = textView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude))
            if abs(parent.measuredHeight - size.height) > 0.5 {
                parent.measuredHeight = size.height
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.selectedRange = textView.selectedRange
        }
    }
}

#elseif os(macOS)
import AppKit

struct AutoSizingStyledCursorTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var isFocused: Bool

    let isEditable: Bool
    @Binding var resignFocusToken: Int
    @Binding var measuredHeight: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let tv = NSTextView()
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainerInset = NSSize(width: 10, height: 10)
        tv.font = NSFont.systemFont(ofSize: 17)
        tv.backgroundColor = NSColor.orange
        tv.textColor = NSColor.black
        tv.isEditable = isEditable
        tv.isSelectable = true
        tv.delegate = context.coordinator

        // ✅ Track width so wrapping matches sheet width (prevents overflow)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineBreakMode = .byWordWrapping

        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }

        if tv.string != text {
            tv.string = text
        }

        tv.isEditable = isEditable
        tv.backgroundColor = NSColor.orange
        tv.textColor = NSColor.black

        // Selection
        let len = (tv.string as NSString).length
        let loc = max(0, min(selectedRange.location, len))
        let slen = max(0, min(selectedRange.length, len - loc))
        tv.setSelectedRange(NSRange(location: loc, length: slen))

        // Resign request
        if context.coordinator.lastResignToken != resignFocusToken {
            context.coordinator.lastResignToken = resignFocusToken
            tv.window?.makeFirstResponder(nil)
            isFocused = false
        }

        // ✅ Measure height after layout
        DispatchQueue.main.async {
            tv.layoutManager?.ensureLayout(for: tv.textContainer!)
            let used = tv.layoutManager?.usedRect(for: tv.textContainer!).height ?? 0
            let h = used + tv.textContainerInset.height * 2
            if abs(measuredHeight - h) > 0.5 {
                measuredHeight = h
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoSizingStyledCursorTextView
        var lastResignToken: Int = 0

        init(_ parent: AutoSizingStyledCursorTextView) {
            self.parent = parent
            self.lastResignToken = parent.resignFocusToken
        }

        func textDidBeginEditing(_ notification: Notification) { parent.isFocused = true }
        func textDidEndEditing(_ notification: Notification) { parent.isFocused = false }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string

            tv.layoutManager?.ensureLayout(for: tv.textContainer!)
            let used = tv.layoutManager?.usedRect(for: tv.textContainer!).height ?? 0
            let h = used + tv.textContainerInset.height * 2
            if abs(parent.measuredHeight - h) > 0.5 {
                parent.measuredHeight = h
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.selectedRange = tv.selectedRange()
        }
    }
}
#endif
