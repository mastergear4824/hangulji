// Sources/Hangulji/HanguljiInputController.swift
import Cocoa
import InputMethodKit
import HanguljiCore

@objc(HanguljiInputController)
public class HanguljiInputController: IMKInputController {
    private var composer = HanguljiComposer()

    // macOS 가상 키코드
    private enum Key {
        static let enter: UInt16 = 36
        static let space: UInt16 = 49
        static let backspace: UInt16 = 51
        static let escape: UInt16 = 53
    }

    public override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown,
              let client = sender as? IMKTextInput & NSObjectProtocol else { return false }

        // 수정키 조합(cmd/ctrl/opt)은 조합만 커밋하고 통과
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            commitComposition(to: client)
            return false
        }

        switch event.keyCode {
        case Key.backspace:
            guard !composer.isEmpty else { return false }
            composer.backspace()
            updateMarkedText(client)
            return true
        case Key.enter:
            guard !composer.isEmpty else { return false }
            commitComposition(to: client)
            return true
        case Key.escape:
            guard !composer.isEmpty else { return false }
            composer.clear()
            updateMarkedText(client)
            return true
        case Key.space:
            guard !composer.isEmpty else { return false }
            commitComposition(to: client)   // Task 9에서 변환 시작으로 교체
            return false
        default:
            break
        }

        guard let chars = event.characters, chars.count == 1, let ch = chars.first else {
            commitComposition(to: client)
            return false
        }

        if composer.insert(ch) {
            updateMarkedText(client)
            return true
        }

        // 일본어 구두점 (스펙 §3)
        if ch == "." || ch == "," {
            commitComposition(to: client)
            insert(ch == "." ? "。" : "、", to: client)
            return true
        }

        // 그 외(영숫자 등): 조합 커밋 후 시스템에 넘김
        commitComposition(to: client)
        return false
    }

    // MARK: - 조합 표시/커밋

    private func updateMarkedText(_ client: IMKTextInput) {
        let text = composer.markedText
        let attributed = NSAttributedString(
            string: text,
            attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue]
        )
        client.setMarkedText(
            attributed,
            selectionRange: NSRange(location: text.utf16.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    private func insert(_ text: String, to client: IMKTextInput) {
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private func commitComposition(to client: IMKTextInput) {
        guard !composer.isEmpty else { return }
        insert(composer.markedText, to: client)
        composer.clear()
        updateMarkedText(client)  // 빈 문자열로 마크드 텍스트 해제
    }

    // 포커스 이동/클릭 시 조합 커밋
    public override func commitComposition(_ sender: Any!) {
        if let client = sender as? IMKTextInput { commitComposition(to: client) }
    }

    public override func deactivateServer(_ sender: Any!) {
        if let client = sender as? IMKTextInput { commitComposition(to: client) }
    }
}
