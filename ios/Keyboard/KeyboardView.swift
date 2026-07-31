// ios/Keyboard/KeyboardView.swift
import SwiftUI

/// 키보드 판(plane) — UI 전용 상태. KeyboardModel은 이 개념을 모른다.
private enum Plane {
    case letters, numeric, symbols, emoji
}

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    weak var controller: KeyboardViewController?
    /// viewDidLoad에서 1회만 읽어 전달됨 — SwiftUI/UIKit 타이밍 이슈 회피(코디네이터 지시).
    let needsInputModeSwitchKey: Bool

    @State private var plane: Plane = .letters

    private let row1 = [("ㅂ", "q", "ㅃ", "Q"), ("ㅈ", "w", "ㅉ", "W"), ("ㄷ", "e", "ㄸ", "E"),
                        ("ㄱ", "r", "ㄲ", "R"), ("ㅅ", "t", "ㅆ", "T"), ("ㅛ", "y", "ㅛ", "y"),
                        ("ㅕ", "u", "ㅕ", "u"), ("ㅑ", "i", "ㅑ", "i"), ("ㅐ", "o", "ㅒ", "O"),
                        ("ㅔ", "p", "ㅖ", "P")]
    private let row2 = [("ㅁ", "a"), ("ㄴ", "s"), ("ㅇ", "d"), ("ㄹ", "f"), ("ㅎ", "g"),
                        ("ㅗ", "h"), ("ㅓ", "j"), ("ㅏ", "k"), ("ㅣ", "l")]
    private let row3 = [("ㅋ", "z"), ("ㅌ", "x"), ("ㅊ", "c"), ("ㅍ", "v"),
                        ("ㅠ", "b"), ("ㅜ", "n"), ("ㅡ", "m")]

    private let emojiList: [String] = [
        "😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂", "🙂", "🙃",
        "😉", "😊", "😇", "🥰", "😍", "🤩", "😘", "😗", "😋", "😜",
        "🤪", "🤔", "🤨", "😎", "🥳", "😢", "😭", "😡", "😱", "🥺",
        "👍", "👎", "👌", "✌️", "🤞", "🤙", "👋", "🙌", "👏", "🙏",
        "💪", "👊", "✊", "🤝", "👉", "👆", "👇", "☝️", "🤚", "🖐️",
        "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "💕", "💖",
        "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯",
        "🦁", "🐮", "🐷", "🐸", "🐵", "🐔", "🐧", "🐦", "🐴", "🦄",
        "🍎", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🍒", "🍑", "🍍",
        "🥑", "🍔", "🍕", "🌭", "🍟", "🍿", "🍩", "🍰", "🍫", "☕️",
        "⚽️", "🏀", "🏈", "⚾️", "🎾", "🏐", "🎱", "🎮", "🎲", "🎸",
        "💡", "📱", "💻", "📷", "🎁", "✅", "❌", "⭐️", "✨", "🎉",
    ]
    private let emojiColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 8)

    private let keyHeight: CGFloat = 43
    private let keyCornerRadius: CGFloat = 4.6
    /// 네이티브 키보드의 행 슬롯 높이 — 4개 슬롯(216pt) + 후보 바(44pt) = 260pt(키보드 창 높이)
    private let slotHeight: CGFloat = 54

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
        VStack(spacing: 0) {
            candidateBar            // height 44, unchanged content
            switch plane {
            case .letters: lettersPlane
            case .numeric: numericPlane
            case .symbols: symbolsPlane
            case .emoji: emojiPlane
            }
        }
        .padding(.horizontal, 3)
        // 호스팅 컨트롤러의 고유 콘텐츠 크기를 260으로 강제 고정 — 이게 없으면 SwiftUI의
        // 계산된 이상적 크기가 view.heightAnchor 제약과 어긋나 UIKit이 더 큰 높이로
        // 렌더링할 수 있다(바 44 + 4×54 슬롯 = 260, 모든 판에서 동일하게 성립).
        .frame(height: 260, alignment: .top)
        .background(Color.clear)
    }

    // MARK: Planes — 각 판은 정확히 216pt(4×54) 사용, 바 44pt와 합쳐 총 260pt 유지

    private var lettersPlane: some View {
        Group {
            keySlot { keyRow(row1.map { model.isShifted ? ($0.2, $0.3) : ($0.0, $0.1) }) }
            keySlot { keyRow(row2).padding(.horizontal, 20) }
            keySlot {
                HStack(spacing: 6) {
                    shiftKey
                    Spacer(minLength: 10)
                    keyRow(row3)
                    Spacer(minLength: 10)
                    specialKey(systemName: "delete.left", width: 46) { model.tapBackspace() }
                }
            }
            keySlot {
                HStack(spacing: 6) {
                    specialKey("123", width: 46) { plane = .numeric }
                    // 시스템 지구본과 중복되므로, 다른 입력 소스가 실제로 있을 때만 표시
                    if needsInputModeSwitchKey {
                        GlobeButton(controller: controller).frame(width: 46, height: keyHeight)
                    }
                    specialKey(systemName: "face.smiling", width: 46) { plane = .emoji }
                    spaceKey
                    specialKey(systemName: "return", width: 88) { model.tapEnter() }
                }
            }
        }
    }

    private var numericPlane: some View {
        Group {
            keySlot { symbolRow(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]) }
            keySlot { symbolRow(["-", "/", ":", ";", "(", ")", "¥", "&", "@", "\""]) }
            keySlot {
                HStack(spacing: 6) {
                    specialKey("#+=", width: 46) { plane = .symbols }
                    Spacer(minLength: 10)
                    symbolRow(["。", "、", "?", "!", "ー", "'"])
                    Spacer(minLength: 10)
                    specialKey(systemName: "delete.left", width: 46) { model.tapBackspace() }
                }
            }
            keySlot { backToLettersRow }
        }
    }

    private var symbolsPlane: some View {
        Group {
            keySlot { symbolRow(["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]) }
            keySlot { symbolRow(["_", "\\", "|", "~", "<", ">", "$", "£", "¥", "·"]) }
            keySlot {
                HStack(spacing: 6) {
                    specialKey("123", width: 46) { plane = .numeric }
                    Spacer(minLength: 10)
                    symbolRow(["。", "、", "?", "!", "ー", "'"])
                    Spacer(minLength: 10)
                    specialKey(systemName: "delete.left", width: 46) { model.tapBackspace() }
                }
            }
            keySlot { backToLettersRow }
        }
    }

    /// 이모지 그리드가 4개 키 슬롯 영역(216pt)을 대체 — 스크롤 그리드 + 자체 하단 행으로 구성
    private var emojiPlane: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: emojiColumns, spacing: 6) {
                    ForEach(emojiList, id: \.self) { emoji in
                        Button { model.tapSymbol(emoji) } label: {
                            Text(emoji)
                                .font(.system(size: 30))
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)
            }
            .frame(maxHeight: .infinity)
            keySlot {
                HStack(spacing: 6) {
                    specialKey("한글", width: 46) { plane = .letters }
                    specialKey(systemName: "delete.left", width: 46) { model.tapBackspace() }
                    spaceKey
                    specialKey(systemName: "return", width: 88) { model.tapEnter() }
                }
            }
        }
        .frame(height: 4 * slotHeight)
    }

    /// 숫자·기호 판 공용 하단 행: [한글(복귀)][😊][스페이스][⏎]
    private var backToLettersRow: some View {
        HStack(spacing: 6) {
            specialKey("한글", width: 46) { plane = .letters }
            specialKey(systemName: "face.smiling", width: 46) { plane = .emoji }
            spaceKey
            specialKey(systemName: "return", width: 88) { model.tapEnter() }
        }
    }

    /// 네이티브 키보드의 행 슬롯: 54pt 슬롯 안에 43pt 키를 수직 중앙 배치 (4×54 = 216 + 바 44 = 260)
    private func keySlot<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().frame(height: keyHeight).frame(maxWidth: .infinity).frame(height: slotHeight)
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
            Image(systemName: model.isShifted ? "shift.fill" : "shift")
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
            Group {
                if isComposingOrSelecting {
                    Text("변환")
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                } else {
                    // 네이티브 스타일 입력 소스 배지 — 오른쪽 정렬, 옅은 회색
                    Text("한글지")
                        .font(.system(size: 11))
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 8)
                }
            }
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

    /// 숫자·기호 판의 문자 키 — 조합과 무관하므로 전부 model.tapSymbol로 전송 (ー는 tapSymbol 내부에서
    /// 조합에 들어가도록 특별 처리되어 있어 그대로 재사용됨)
    private func symbolRow(_ symbols: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(symbols, id: \.self) { symbol in
                Button { model.tapSymbol(symbol) } label: {
                    Text(symbol)
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

    /// 텍스트 라벨 특수키(123·#+=·한글) — 네이티브도 이 셋은 텍스트로 표시.
    private func specialKey(_ label: String, width: CGFloat = 46, fontSize: CGFloat = 16,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: fontSize))
                .foregroundColor(.primary)
                .frame(width: width, height: keyHeight)
                .background(specialKeyFillColor)
                .cornerRadius(keyCornerRadius)
                .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    /// SF Symbol 특수키(⌫·⏎·😊 등 네이티브가 아이콘으로 그리는 키) — 색상 이모지·텍스트 글리프
    /// 대신 시스템 심볼을 써서 네이티브 키보드와 아이콘을 동일하게 맞춘다.
    private func specialKey(systemName: String, width: CGFloat = 46,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
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
