// ios/Keyboard/KeyboardView.swift
import SwiftUI

/// 키보드 판(plane) — UI 전용 상태. KeyboardModel은 이 개념을 모른다.
private enum Plane {
    case letters, numeric, symbols, emoji
}

/// 롱프레스 팝업을 그리는 데 필요한 데이터 — 앵커 프리퍼런스로 row1 키에서 루트까지 흘려보낸다.
/// keySlot의 zIndex로는 형제(candidateBar)를 이길 수 없어서, 팝업을 키 트리 안이 아니라
/// KeyboardView 루트의 최상위 오버레이(overlayPreferenceValue)에서 그리기 위한 우회로.
private struct CalloutData: Equatable {
    let latin: String
    let jamo: String
    let variantJamo: String
    let variantSelected: Bool
    let anchor: Anchor<CGRect>

    static func == (l: Self, r: Self) -> Bool {
        l.latin == r.latin && l.variantSelected == r.variantSelected
    }
}

private struct CalloutPreferenceKey: PreferenceKey {
    static var defaultValue: CalloutData? = nil
    static func reduce(value: inout CalloutData?, nextValue: () -> CalloutData?) {
        value = nextValue() ?? value
    }
}

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    weak var controller: KeyboardViewController?
    /// viewDidLoad에서 1회만 읽어 전달됨 — SwiftUI/UIKit 타이밍 이슈 회피(코디네이터 지시).
    let needsInputModeSwitchKey: Bool

    @State private var plane: Plane = .letters
    /// 롱프레스로 팝업 중인 row1 변형키의 latin(기본, 비시프트) 식별자 — 동시에 하나만 존재.
    @State private var calloutKey: String? = nil
    /// 팝업이 떠 있는 동안의 선택 칸 — false=기본(왼쪽), true=변형(오른쪽). 팝업이 뜰 때마다 false로 리셋.
    @State private var selectedVariant = false

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

    // 픽셀 실측 캘리브레이션 (라이브 나란히 측정 — cycle-2 네이티브 vs cycle-3 한글지, 시각 확증):
    //   네이티브 렌더: 행 top 591/645/699/753, 피치 54, 키 42.7 | 직전 우리 렌더(44/42/9/4): 600/피치51/키41.7
    //   보정: 바 −9, 키 +1, 행간 +2 → 35/43/11/3 (합 243, 프레임 335 유지). 변경 시 반드시 재실측.
    private let totalHeight: CGFloat = 243
    private let barHeight: CGFloat = 35
    private let keyHeight: CGFloat = 43
    private let rowGap: CGFloat = 11
    private let bottomMargin: CGFloat = 3
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
                // 네이티브 실측 RGB(173, 179, 189) 정확값 — 이전 0.68/0.70/0.74는 산술상 근사치였음.
                : UIColor(red: 173 / 255, green: 179 / 255, blue: 189 / 255, alpha: 1)
        })
    }

    private var isComposingOrSelecting: Bool {
        !model.preview.isEmpty || !model.candidates.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            candidateBar            // height = barHeight
            rowsBlock
        }
        .padding(.horizontal, 3)
        // 호스팅 컨트롤러의 고유 콘텐츠 크기를 강제 고정 — 이게 없으면 SwiftUI의 계산된
        // 이상적 크기가 view.heightAnchor 제약과 어긋나 UIKit이 다른 높이로 렌더링할 수 있다.
        .frame(height: totalHeight, alignment: .top)
        .background(Color.clear)
        // 롱프레스 팝업 — 트리 최상위 오버레이라 candidateBar를 포함한 모든 형제 위에 그려진다.
        .overlayPreferenceValue(CalloutPreferenceKey.self) { data in
            GeometryReader { proxy in
                if let data {
                    let rect = proxy[data.anchor]
                    calloutPanel(data)
                        .position(x: min(max(rect.midX, 55), proxy.size.width - 55),
                                  y: rect.minY - 26)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// 기본·변형 두 칸(44×44, 간격 4)을 담은 흰 패널 — 선택된 칸만 파란 배경 + 흰 글자.
    private func calloutPanel(_ data: CalloutData) -> some View {
        HStack(spacing: 4) {
            variantCell(data.jamo, selected: !data.variantSelected)
            variantCell(data.variantJamo, selected: data.variantSelected)
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 10).fill(keyFillColor))
        .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 1)
    }

    private func variantCell(_ text: String, selected: Bool) -> some View {
        Text(text)
            .font(.system(size: 24))
            .foregroundColor(selected ? .white : .primary)
            .frame(width: 44, height: 44)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.systemBlue))
                }
            }
    }

    /// 4개 키 행 블록 + 하단 여백. 모든 판에서 barHeight + 4×keyHeight + 3×rowGap + bottomMargin = totalHeight.
    private var rowsBlock: some View {
        VStack(spacing: rowGap) {
            switch plane {
            case .letters: lettersPlane
            case .numeric: numericPlane
            case .symbols: symbolsPlane
            case .emoji: emojiPlane
            }
        }
        .padding(.bottom, bottomMargin)
    }

    // MARK: Planes

    private var lettersPlane: some View {
        Group {
            keySlot { row1Row }   // 팝업은 이제 루트 오버레이(overlayPreferenceValue)에서 그려짐
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
                    specialKey("😀", width: 46, fontSize: 23) { plane = .emoji }
                    spaceKey
                    specialKey(systemName: "return", width: 88) { model.tapEnter() }
                }
            }
        }
    }

    /// row1(ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ) 전용 렌더 — 쌍자음·복모음 변형이 있는 7개 키(ㅂㅈㄷㄱㅅㅐㅔ)만
    /// 롱프레스 팝업(VariantKeyButton)으로 그리고, 나머지 3개(ㅛㅕㅑ)와 시프트 중엔 기존 방식 그대로.
    /// 시프트가 이미 켜져 있으면 표시되는 글자 자체가 변형이라 더 보여줄 변형이 없으므로 롱프레스 불필요.
    private var row1Row: some View {
        HStack(spacing: 6) {
            ForEach(row1, id: \.1) { jamo, latin, shiftedJamo, shiftedLatin in
                if model.isShifted {
                    keyButton(shiftedJamo) { model.tapKey(Character(shiftedLatin)) }
                } else if shiftedLatin != latin {
                    VariantKeyButton(jamo: jamo, latin: latin,
                                     variantJamo: shiftedJamo, variantLatin: shiftedLatin,
                                     keyHeight: keyHeight, keyCornerRadius: keyCornerRadius,
                                     keyFillColor: keyFillColor,
                                     calloutKey: $calloutKey, selectedVariant: $selectedVariant) { ch in
                        model.tapKey(ch)
                    }
                } else {
                    keyButton(jamo) { model.tapKey(Character(latin)) }
                }
            }
        }
    }

    /// row1/row2/row3가 공유하는 평범한 키 라벨 스타일 — VariantKeyButton과 동일한 룩을 낸다.
    private func keyButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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

    /// 이모지 그리드가 4개 키 행 블록을 대체 — 스크롤 그리드 + 자체 하단 행 (합계는 rowsBlock과 동일).
    private var emojiPlane: some View {
        VStack(spacing: rowGap) {
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
        .frame(height: 4 * keyHeight + 3 * rowGap)
    }

    /// 숫자·기호 판 공용 하단 행: [한글(복귀)][😊][스페이스][⏎]
    private var backToLettersRow: some View {
        HStack(spacing: 6) {
            specialKey("한글", width: 46) { plane = .letters }
            specialKey("😀", width: 46, fontSize: 23) { plane = .emoji }
            spaceKey
            specialKey(systemName: "return", width: 88) { model.tapEnter() }
        }
    }

    /// 행 높이를 정확히 keyHeight로 고정 — 행 간 간격은 부모 VStack(spacing: rowGap)이 담당.
    private func keySlot<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().frame(height: keyHeight)
    }

    /// 조합 중인 가나는 입력창에 인라인(마크드 텍스트)으로 표시되므로, 여기서는 후보 선택 중에만
    /// 내용을 보여준다. 비어 있을 때는 네이티브처럼 1/3·2/3 지점에 옅은 세로 틱 구분선만 표시.
    private var candidateBar: some View {
        Group {
            if model.candidates.isEmpty {
                GeometryReader { geo in
                    ZStack {
                        ForEach([1, 2], id: \.self) { i in
                            Rectangle()
                                .fill(Color(UIColor.separator))
                                .frame(width: 1, height: 26)
                                .position(x: geo.size.width * CGFloat(i) / 3, y: geo.size.height / 2)
                        }
                    }
                }
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
        .frame(height: barHeight)
        .background(Color.clear)
    }

    private var shiftKey: some View {
        Button { model.toggleShift() } label: {
            Image(systemName: model.isShifted ? "shift.fill" : "shift")
                .font(.system(size: 22, weight: .regular))
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
    private func specialKey(_ label: String, width: CGFloat = 46, fontSize: CGFloat = 17,
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
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(.primary)
                .frame(width: width, height: keyHeight)
                .background(specialKeyFillColor)
                .cornerRadius(keyCornerRadius)
                .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

/// 롱프레스(≥0.35s) 시 위쪽에 기본·변형 두 칸짜리 스와이프 선택 팝업을 보여주는 row1 전용 키
/// (네이티브 한글 키보드의 쌍자음/복모음 롱프레스 팝업과 동일한 상호작용):
/// 짧게 누르고 떼면 기본(latin) 입력. 길게 눌러 팝업이 뜨면 처음엔 기본 칸이 선택된 채 시작하고,
/// 오른쪽으로 반 칸 이상 드래그하면 변형 칸으로, 다시 왼쪽으로 돌아오면 기본 칸으로 선택이 바뀌며,
/// 뗀 시점의 선택 칸이 입력된다.
/// 팝업 자체는 이 뷰가 그리지 않는다 — anchorPreference로 위치(bounds)만 흘려보내고, 실제 렌더는
/// KeyboardView 루트의 overlayPreferenceValue가 맡는다(형제 뷰 위로 확실히 그려지도록).
private struct VariantKeyButton: View {
    let jamo: String
    let latin: String
    let variantJamo: String
    let variantLatin: String
    let keyHeight: CGFloat
    let keyCornerRadius: CGFloat
    let keyFillColor: Color
    @Binding var calloutKey: String?
    @Binding var selectedVariant: Bool
    let onTap: (Character) -> Void

    @State private var pressToken: UUID?
    @State private var isPressed = false

    private static let holdThreshold: TimeInterval = 0.35
    private static let dragThreshold: CGFloat = 22
    private var isShowingCallout: Bool { calloutKey == latin }

    var body: some View {
        Text(jamo)
            .font(.system(size: 23))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, minHeight: keyHeight)
            .background(keyFillColor)
            .overlay(isPressed ? Color.black.opacity(0.12) : Color.clear)
            .cornerRadius(keyCornerRadius)
            .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 1)
            .contentShape(Rectangle())
            .anchorPreference(key: CalloutPreferenceKey.self, value: .bounds) { anchor in
                isShowingCallout
                    ? CalloutData(latin: latin, jamo: jamo, variantJamo: variantJamo,
                                   variantSelected: selectedVariant, anchor: anchor)
                    : nil
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isPressed = true
                        if isShowingCallout {
                            selectedVariant = value.translation.width > Self.dragThreshold
                        }
                        guard pressToken == nil else { return }
                        let token = UUID()
                        pressToken = token
                        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdThreshold) {
                            // 그 사이 손을 뗐거나(다른 프레스가 시작됐으면) 무시 — 낡은 타이머 방지.
                            guard pressToken == token else { return }
                            selectedVariant = false   // 네이티브처럼 팝업 등장 시 기본 칸이 먼저 선택됨
                            calloutKey = latin
                        }
                    }
                    .onEnded { _ in
                        if isShowingCallout {
                            onTap(Character(selectedVariant ? variantLatin : latin))
                        } else {
                            onTap(Character(latin))
                        }
                        pressToken = nil
                        calloutKey = nil
                        isPressed = false
                        selectedVariant = false
                    }
            )
    }
}
