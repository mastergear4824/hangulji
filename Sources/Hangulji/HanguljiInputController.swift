// Sources/Hangulji/HanguljiInputController.swift
import Cocoa
import InputMethodKit
import HanguljiCore
import HanguljiConversion

@objc(HanguljiInputController)
public class HanguljiInputController: IMKInputController {
    private var composer = HanguljiComposer()

    private enum Mode {
        case composing
        case selecting(candidates: [String], index: Int)
    }
    private var mode: Mode = .composing
    private let panel = CandidatePanel()
    /// 사전 로드가 무거우므로 lazy — 최초 변환에 지연이 있을 수 있음 (알려진 트레이드오프)
    private static let converter = KanjiConverter()

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

        if case .selecting(let candidates, let index) = mode {
            return handleSelecting(event, client: client, candidates: candidates, index: index)
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
            startConversion(client)
            return true
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
        if case .selecting(let candidates, let index) = mode {
            commitCandidate(candidates[index], client)
            return
        }
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
        panel.hide()
    }

    // MARK: - 변환 (selecting)

    private func startConversion(_ client: IMKTextInput) {
        guard let reading = composer.reading else {
            // 매핑 불가 음절 포함 → 변환 불가, 그대로 커밋 (스펙 §3)
            commitComposition(to: client)
            return
        }
        let candidates = Self.converter.candidateList(for: reading, max: 9)
        guard !candidates.isEmpty else { return }
        mode = .selecting(candidates: candidates, index: 0)
        showSelection(client)
    }

    private func handleSelecting(_ event: NSEvent, client: IMKTextInput,
                                 candidates: [String], index: Int) -> Bool {
        switch event.keyCode {
        case Key.space, 125:  // Space/↓: 다음 후보
            mode = .selecting(candidates: candidates, index: (index + 1) % candidates.count)
            showSelection(client)
            return true
        case 126:             // ↑: 이전 후보
            mode = .selecting(candidates: candidates,
                              index: (index - 1 + candidates.count) % candidates.count)
            showSelection(client)
            return true
        case Key.enter:
            commitCandidate(candidates[index], client)
            return true
        case Key.escape, Key.backspace:  // 변환 취소 → composing 복귀 (스펙 §3)
            mode = .composing
            panel.hide()
            updateMarkedText(client)
            return true
        default:
            break
        }

        if let chars = event.characters, chars.count == 1, let ch = chars.first {
            // 숫자키로 후보 직접 선택
            if let n = ch.wholeNumberValue, (1...candidates.count).contains(n) {
                commitCandidate(candidates[n - 1], client)
                return true
            }
            // 새 타이핑: 현재 후보 확정 후 새 조합 시작
            if Keymap.jamo(for: ch) != nil || ch == "-" {
                commitCandidate(candidates[index], client)
                _ = composer.insert(ch)
                updateMarkedText(client)
                return true
            }
        }
        // 그 외 키: 현재 후보 확정 후 시스템에 넘김
        commitCandidate(candidates[index], client)
        return false
    }

    private func showSelection(_ client: IMKTextInput) {
        guard case .selecting(let candidates, let index) = mode else { return }
        // 마크드 텍스트에 현재 후보 표시
        let attributed = NSAttributedString(
            string: candidates[index],
            attributes: [.underlineStyle: NSUnderlineStyle.thick.rawValue]
        )
        client.setMarkedText(
            attributed,
            selectionRange: NSRange(location: candidates[index].utf16.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        // 캐럿 위치 아래에 후보창
        var lineRect = NSRect.zero
        client.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineRect)
        panel.show(candidates: candidates, selected: index,
                   topLeft: NSPoint(x: lineRect.origin.x, y: lineRect.origin.y - 4))
    }

    private func commitCandidate(_ text: String, _ client: IMKTextInput) {
        insert(text, to: client)
        composer.clear()
        mode = .composing
        panel.hide()
        updateMarkedText(client)
    }
}
