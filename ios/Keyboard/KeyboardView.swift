// ios/Keyboard/KeyboardView.swift
import SwiftUI

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    weak var controller: KeyboardViewController?

    private let row1 = [("ㅂ", "q", "ㅃ", "Q"), ("ㅈ", "w", "ㅉ", "W"), ("ㄷ", "e", "ㄸ", "E"),
                        ("ㄱ", "r", "ㄲ", "R"), ("ㅅ", "t", "ㅆ", "T"), ("ㅛ", "y", "ㅛ", "y"),
                        ("ㅕ", "u", "ㅕ", "u"), ("ㅑ", "i", "ㅑ", "i"), ("ㅐ", "o", "ㅒ", "O"),
                        ("ㅔ", "p", "ㅖ", "P")]
    private let row2 = [("ㅁ", "a"), ("ㄴ", "s"), ("ㅇ", "d"), ("ㄹ", "f"), ("ㅎ", "g"),
                        ("ㅗ", "h"), ("ㅓ", "j"), ("ㅏ", "k"), ("ㅣ", "l")]
    private let row3 = [("ㅋ", "z"), ("ㅌ", "x"), ("ㅊ", "c"), ("ㅍ", "v"),
                        ("ㅠ", "b"), ("ㅜ", "n"), ("ㅡ", "m")]

    private let keyHeight: CGFloat = 43
    private let keyCornerRadius: CGFloat = 4.6

    // 시스템 키보드 톤 — 라이트: 흰 키/회색 특수키, 다크: 진회색 키/더 진한 특수키. 액센트(블루) 사용 금지.
    private var keyFillColor: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 0.42, alpha: 1)
                : UIColor.white
        })
    }

    private var specialKeyFillColor: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 0.28, alpha: 1)
                : UIColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1)
        })
    }

    private var isComposingOrSelecting: Bool {
        !model.preview.isEmpty || !model.candidates.isEmpty
    }

    var body: some View {
        VStack(spacing: 11) {
            candidateBar
            keyRow(row1.map { model.isShifted ? ($0.2, $0.3) : ($0.0, $0.1) })
            keyRow(row2)
                .padding(.horizontal, 20)
            HStack(spacing: 6) {
                shiftKey
                Spacer(minLength: 10)
                keyRow(row3)
                Spacer(minLength: 10)
                specialKey("⌫", width: 46) { model.tapBackspace() }
            }
            HStack(spacing: 6) {
                GlobeButton(controller: controller).frame(width: 46, height: keyHeight)
                specialKey("ー", width: 46) { model.tapSymbol("ー") }
                spaceKey
                specialKey("。", width: 46) { model.tapSymbol("。") }
                specialKey("⏎", width: 88) { model.tapEnter() }
            }
        }
        .padding(6)
        .background(Color.clear)
    }

    /// 조합 중인 가나는 입력창에 인라인(마크드 텍스트)으로 표시되므로, 여기서는 후보 선택 중에만
    /// 내용을 보여준다. 네이티브 제안 바 스타일: 배경 박스 없이 구분선으로만 항목을 나눈다.
    private var candidateBar: some View {
        Group {
            if model.candidates.isEmpty {
                Color.clear
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(model.candidates.enumerated()), id: \.offset) { index, candidate in
                            if index > 0 {
                                Rectangle()
                                    .fill(Color(UIColor.separator))
                                    .frame(width: 0.5, height: 20)
                            }
                            Button { model.tapCandidate(index) } label: {
                                Text(candidate)
                                    .font(.system(size: 17))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background {
                                        if index == model.selectedIndex {
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color(UIColor.systemGray4))
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 14)
                            .frame(maxHeight: .infinity)
                        }
                    }
                }
            }
        }
        .frame(height: 44)
        .background(Color.clear)
    }

    private var shiftKey: some View {
        Button { model.toggleShift() } label: {
            Text(model.isShifted ? "⬆" : "⇧")
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .frame(width: 46, height: keyHeight)
                .background(model.isShifted ? keyFillColor : specialKeyFillColor)
                .cornerRadius(keyCornerRadius)
                .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    private var spaceKey: some View {
        Button { model.tapSpace() } label: {
            Text(isComposingOrSelecting ? "변환" : "")
                .font(.system(size: 16))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, minHeight: keyHeight)
                .background(keyFillColor)
                .cornerRadius(keyCornerRadius)
                .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func keyRow(_ keys: [(String, String)]) -> some View {
        HStack(spacing: 6) {
            ForEach(keys, id: \.1) { label, latin in
                Button { model.tapKey(Character(latin)) } label: {
                    Text(label)
                        .font(.system(size: 23))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, minHeight: keyHeight)
                        .background(keyFillColor)
                        .cornerRadius(keyCornerRadius)
                        .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func specialKey(_ label: String, width: CGFloat = 46,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .frame(width: width, height: keyHeight)
                .background(specialKeyFillColor)
                .cornerRadius(keyCornerRadius)
                .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}
