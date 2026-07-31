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

    var body: some View {
        VStack(spacing: 6) {
            candidateBar
            keyRow(row1.map { model.isShifted ? ($0.2, $0.3) : ($0.0, $0.1) })
            keyRow(row2)
            HStack(spacing: 4) {
                controlKey(model.isShifted ? "⬆" : "⇧") { model.toggleShift() }
                keyRow(row3)
                controlKey("⌫") { model.tapBackspace() }
            }
            HStack(spacing: 4) {
                GlobeButton(controller: controller).frame(width: 44)
                controlKey("ー", width: 36) { model.tapSymbol("ー") }
                Button { model.tapSpace() } label: {
                    Text(model.candidates.isEmpty ? "변환·스페이스" : "다음 후보")
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(6)
                }
                controlKey("。", width: 36) { model.tapSymbol("。") }
                controlKey("⏎", width: 44) { model.tapEnter() }
            }
        }
        .padding(6)
        .background(Color(UIColor.secondarySystemBackground))
    }

    private var candidateBar: some View {
        Group {
            if model.candidates.isEmpty {
                Text(model.preview.isEmpty ? " " : model.preview)
                    .font(.system(size: 20))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(model.candidates.enumerated()), id: \.offset) { index, candidate in
                            Button { model.tapCandidate(index) } label: {
                                Text(candidate)
                                    .font(.system(size: 20))
                                    .padding(.horizontal, 6)
                                    .background(index == model.selectedIndex
                                                ? Color.accentColor.opacity(0.25) : Color.clear)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(height: 44)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(6)
    }

    private func keyRow(_ keys: [(String, String)]) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.1) { label, latin in
                Button { model.tapKey(Character(latin)) } label: {
                    Text(label)
                        .font(.system(size: 20))
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func controlKey(_ label: String, width: CGFloat? = nil,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 18))
                .frame(minWidth: width ?? 44, minHeight: 42)
                .frame(maxWidth: width == nil ? 60 : width)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}
