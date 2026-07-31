// ios/Keyboard/KeyboardModel.swift
import Foundation
import HanguljiCore
import HanguljiConversion

protocol TextOutput: AnyObject {
    func insertText(_ s: String)
    func deleteBackward()
}

/// 키보드 상태머신. UIKit 비의존 — 유닛테스트 대상.
/// 의미론은 macOS 셸(스펙 §3)의 iOS 번역: 스페이스=변환/다음 후보, 후보 탭=확정.
final class KeyboardModel: ObservableObject {
    @Published private(set) var preview = ""
    @Published private(set) var candidates: [String] = []
    @Published private(set) var selectedIndex = 0
    @Published var isShifted = false

    weak var output: TextOutput?

    private var composer = HanguljiComposer()
    private static let converter = KanjiConverter()   // 사전 로드 무거움 — 공유 1회

    private var isSelecting: Bool { !candidates.isEmpty }

    func tapKey(_ latin: Character) {
        if isSelecting { commitCandidate(at: selectedIndex) }
        if composer.insert(latin) {
            isShifted = false
            refreshPreview()
        }
    }

    func toggleShift() { isShifted.toggle() }

    func tapSpace() {
        if isSelecting {
            selectedIndex = (selectedIndex + 1) % candidates.count
            preview = candidates[selectedIndex]
            return
        }
        guard !composer.isEmpty else {
            output?.insertText(" ")
            return
        }
        guard let reading = composer.reading else {
            commitComposition()   // 매핑 불가 포함 → 그대로 확정
            return
        }
        let list = Self.converter.candidateList(for: reading, max: 9)
        guard !list.isEmpty else { return }
        candidates = list
        selectedIndex = 0
        preview = list[0]
    }

    func tapCandidate(_ index: Int) {
        guard candidates.indices.contains(index) else { return }
        commitCandidate(at: index)
    }

    func tapEnter() {
        if isSelecting { return commitCandidate(at: selectedIndex) }
        if !composer.isEmpty { return commitComposition() }
        output?.insertText("\n")
    }

    func tapBackspace() {
        if isSelecting {   // 변환 취소 → 가나 조합으로 복귀
            candidates = []
            selectedIndex = 0
            refreshPreview()
            return
        }
        if composer.backspace() {
            refreshPreview()
        } else {
            output?.deleteBackward()
        }
    }

    func tapSymbol(_ s: String) {
        if isSelecting { commitCandidate(at: selectedIndex) }
        if s == "ー" {
            if composer.insert("-") { refreshPreview() }
            return
        }
        if !composer.isEmpty { commitComposition() }
        output?.insertText(s)
    }

    /// 포커스 이탈 등 — 조합 중이면 전부 확정
    func commitAll() {
        if isSelecting { return commitCandidate(at: selectedIndex) }
        if !composer.isEmpty { commitComposition() }
    }

    private func commitComposition() {
        output?.insertText(composer.markedText)
        composer.clear()
        refreshPreview()
    }

    private func commitCandidate(at index: Int) {
        output?.insertText(candidates[index])
        composer.clear()
        candidates = []
        selectedIndex = 0
        preview = ""
    }

    private func refreshPreview() { preview = composer.markedText }
}
