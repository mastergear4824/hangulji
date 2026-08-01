package com.mastergear.hangulji.keyboard

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInParent
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitLongPressOrCancellation
import androidx.compose.material3.Text
import kotlin.math.roundToInt

/** 키 정의: 표시 자모·전송 라틴 + 시프트/롱프레스 변형(변형 없으면 base와 동일) + row1 전용 숫자 힌트.
 *  digit은 Gboard 실측(에뮬레이터 hangulji, 1080x2400@420dpi) 기준 row1(qwertyuiop 자리)에만 부여 —
 *  row2/row3 KeyDef는 인자 생략으로 null 유지, 기존 즉시입력(눌림 즉시 커밋) 경로 그대로. */
private data class KeyDef(
    val label: String, val latin: Char,
    val variantLabel: String, val variantLatin: Char,
    val digit: Char? = null,
) {
    val hasVariant: Boolean get() = latin != variantLatin
}

private val row1 = listOf(
    KeyDef("ㅂ", 'q', "ㅃ", 'Q', '1'), KeyDef("ㅈ", 'w', "ㅉ", 'W', '2'), KeyDef("ㄷ", 'e', "ㄸ", 'E', '3'),
    KeyDef("ㄱ", 'r', "ㄲ", 'R', '4'), KeyDef("ㅅ", 't', "ㅆ", 'T', '5'), KeyDef("ㅛ", 'y', "ㅛ", 'y', '6'),
    KeyDef("ㅕ", 'u', "ㅕ", 'u', '7'), KeyDef("ㅑ", 'i', "ㅑ", 'i', '8'), KeyDef("ㅐ", 'o', "ㅒ", 'O', '9'),
    KeyDef("ㅔ", 'p', "ㅖ", 'P', '0'),
)
private val row2 = "ㅁㄴㅇㄹㅎㅗㅓㅏㅣ".zip("asdfghjkl")
    .map { (label, latin) -> KeyDef(label.toString(), latin, label.toString(), latin) }
private val row3 = "ㅋㅌㅊㅍㅠㅜㅡ".zip("zxcvbnm")
    .map { (label, latin) -> KeyDef(label.toString(), latin, label.toString(), latin) }

/** ?123 판 상태 — Compose 뷰 전용(iOS KeyboardView.swift의 private enum Plane과 동일 개념).
 *  KeyboardModel은 이 개념을 모른다 — 모든 키는 model.tapKey/tapSymbol 등 기존 계약만 사용한다. */
private enum class Plane { LETTERS, NUMERIC, SYMBOLS }

// 숫자·기호 판 슬롯 — ios/Keyboard/KeyboardView.swift numericPlane/symbolsPlane과 1:1 대응.
private val digitRow = listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "0")
private val numericRow2 = listOf("-", "/", ":", ";", "(", ")", "¥", "&", "@", "\"")
private val symbolsRow1 = listOf("[", "]", "{", "}", "#", "%", "^", "*", "+", "=")
private val symbolsRow2 = listOf("_", "\\", "|", "~", "<", ">", "$", "£", "¥", "·")
private val symbolMidRow = listOf("。", "、", "?", "!", "ー", "'")

/** 롱프레스 팝업의 한 칸 — 기본/변형(자모 입력)이거나 숫자(기호 삽입) */
private sealed class CalloutCell(val label: String) {
    class Jamo(label: String, val latin: Char) : CalloutCell(label)
    class Digit(val digit: Char) : CalloutCell(digit.toString())
}

/** 롱프레스 팝업 상태 — 동시에 하나만 존재. 칸 수는 키마다 다름(쌍자음 변형키=3칸, 숫자만=1칸) */
private class CalloutState(
    val key: KeyDef, val keyBounds: Rect, val cells: List<CalloutCell>, initialIndex: Int,
) {
    var selectedIndex by mutableStateOf(initialIndex)
}

/** Gboard 실측 팔레트(에뮬레이터 hangulji, 1080x2400 @420dpi, 영문 QWERTY 도킹 키보드 기준 —
 *  한국어 두벌식 서브타입은 이 환경에서 물리 키보드 컴패니언 상태 버그로 도킹 렌더를 강제하지
 *  못해 대체 실측했으나, 두벌식 레이아웃 미리보기로 행 구조(10/9/7 + 숫자힌트)는 동일 확인함):
 *   패널 배경 RGB(241,240,247) · 키 채움 RGB(255,255,255) · 특수키 톤 RGB(221,226,249) ·
 *   엔터 채움 RGB(178,197,255)(원형, 지름 147px≈56dp) · 글자 RGB(26,27,33) ·
 *   숫자 힌트 RGB(72,73,77) · 모서리 반경 ≈15px≈6dp */
@Composable
fun KeyboardScreen(model: KeyboardModel, onSwitchKeyboard: () -> Unit) {
    val dark = isSystemInDarkTheme()
    val background = if (dark) Color(0xFF2B2B2B) else Color(0xFFF1F0F7)
    val keyColor = if (dark) Color(0xFF6B6B6B) else Color.White
    val specialColor = if (dark) Color(0xFF474747) else Color(0xFFDDE2F9)
    val enterColor = if (dark) Color(0xFF5B7FFF) else Color(0xFFB2C5FF)
    val textColor = if (dark) Color.White else Color(0xFF1A1B21)
    val digitHintColor = if (dark) Color(0xFFBBBBBB) else Color(0xFF48494D)
    var callout by remember { mutableStateOf<CalloutState?>(null) }
    var plane by remember { mutableStateOf(Plane.LETTERS) }

    // 유휴: "한글지" · 조합/선택 중: "변환" (기능은 tapSpace로 동일 — 라벨만 Gboard 톤에 맞춤)
    val spaceLabel = if (model.preview.isEmpty() && model.candidates.isEmpty()) "한글지" else "변환"

    Box {
        Column(
            // Gboard 실측: 패널 배경은 화면 끝까지 칠하되 키 내용은 제스처 내비게이션 인셋만큼
            // 위로 띄운다(실측 여백 ~61dp) — 안 그러면 시스템 "키보드 숨기기" 어포던스가 엔터
            // 원형 위에 겹친다(실기 확인).
            modifier = Modifier.fillMaxWidth().background(background)
                .windowInsetsPadding(WindowInsets.navigationBars)
                .padding(horizontal = 5.dp, vertical = 3.dp),
            // Gboard 실측 행간 간격 ≈32px≈12dp (기존 6dp에서 조정 — 2라운드 실측 피드백)
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            CandidateBar(model, textColor)
            when (plane) {
                Plane.LETTERS -> {
                    KeyRow(row1, model, keyColor, textColor, digitHintColor, onCallout = { callout = it })
                    KeyRow(row2, model, keyColor, textColor, digitHintColor, onCallout = { callout = it })
                    Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                        SpecialKey(if (model.isShifted) "⬆" else "⇧", specialColor, textColor,
                            Modifier.width(44.dp)) { model.toggleShift() }
                        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                            for (key in row3) {
                                KeyCap(key, model, keyColor, textColor, digitHintColor, Modifier.weight(1f),
                                    onCallout = { callout = it })
                            }
                        }
                        SpecialKey("⌫", specialColor, textColor, Modifier.width(44.dp)) {
                            model.tapBackspace()
                        }
                    }
                    // Gboard 순서: [?123][ー][🌐][space][。][enter-원형] — ?123은 숫자판 진입.
                    SymbolBottomRow("?123", { plane = Plane.NUMERIC; callout = null },
                        model, keyColor, specialColor, enterColor, textColor, spaceLabel, onSwitchKeyboard)
                }
                Plane.NUMERIC -> {
                    // ios/Keyboard/KeyboardView.swift numericPlane과 동일 구조(1-0 / 기호 / #+= 전환 / 복귀).
                    SymbolRow(digitRow, model, keyColor, textColor)
                    SymbolRow(numericRow2, model, keyColor, textColor)
                    SymbolThirdRow("#+=", { plane = Plane.SYMBOLS },
                        model, keyColor, specialColor, textColor)
                    SymbolBottomRow("한글", { plane = Plane.LETTERS },
                        model, keyColor, specialColor, enterColor, textColor, spaceLabel, onSwitchKeyboard)
                }
                Plane.SYMBOLS -> {
                    // ios/Keyboard/KeyboardView.swift symbolsPlane과 동일 구조(123 전환 / 복귀는 numeric과 동일).
                    SymbolRow(symbolsRow1, model, keyColor, textColor)
                    SymbolRow(symbolsRow2, model, keyColor, textColor)
                    SymbolThirdRow("123", { plane = Plane.NUMERIC },
                        model, keyColor, specialColor, textColor)
                    SymbolBottomRow("한글", { plane = Plane.LETTERS },
                        model, keyColor, specialColor, enterColor, textColor, spaceLabel, onSwitchKeyboard)
                }
            }
        }
        callout?.let { CalloutPopup(it, keyColor, textColor) }
    }
}

/** 후보/조합 미리보기 — Gboard 실측대로 패널 배경에 투명(별도 박스 없음), 내용 없으면 아무것도
 *  그리지 않는다(Gboard는 툴바 아이콘을 보여주지만 우리는 툴바 기능이 없어 완전히 비움). */
@Composable
private fun CandidateBar(model: KeyboardModel, textColor: Color) {
    if (model.preview.isEmpty() && model.candidates.isEmpty()) return
    Box(
        Modifier.fillMaxWidth().height(44.dp),
        contentAlignment = Alignment.CenterStart,
    ) {
        if (model.candidates.isEmpty()) {
            Text(model.preview, color = textColor, fontSize = 20.sp,
                modifier = Modifier.padding(horizontal = 10.dp))
        } else {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(14.dp),
                modifier = Modifier.padding(horizontal = 10.dp)) {
                itemsIndexed(model.candidates) { index, candidate ->
                    Text(
                        candidate, color = textColor, fontSize = 20.sp,
                        modifier = Modifier
                            .background(
                                if (index == model.selectedIndex) Color(0x3345A0FF)
                                else Color.Transparent,
                                RoundedCornerShape(4.dp))
                            .padding(horizontal = 6.dp)
                            .clickable { model.tapCandidate(index) },
                    )
                }
            }
        }
    }
}

@Composable
private fun KeyRow(
    keys: List<KeyDef>, model: KeyboardModel, keyColor: Color, textColor: Color, digitHintColor: Color,
    onCallout: (CalloutState?) -> Unit,
) {
    Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        for (key in keys) {
            KeyCap(key, model, keyColor, textColor, digitHintColor, Modifier.weight(1f), onCallout)
        }
    }
}

/** 숫자·기호 판의 문자 키 — 조합과 무관하므로 전부 model.tapSymbol로 전송한다(ー는 tapSymbol
 *  내부에서 조합에 들어가도록 특별 처리되어 있어 그대로 재사용됨 — model.tapSymbol("ー") 참조).
 *  롱프레스 팝업 없음(Gboard 실측·iOS symbolRow 모두 숫자·기호 키에는 변형 팝업이 없다). */
@Composable
private fun SymbolKey(
    symbol: String, model: KeyboardModel, keyColor: Color, textColor: Color, modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier.height(47.dp)
            .background(keyColor, RoundedCornerShape(6.dp))
            .clickable { model.tapSymbol(symbol) },
        contentAlignment = Alignment.Center,
    ) {
        Text(symbol, color = textColor, fontSize = 20.sp, textAlign = TextAlign.Center)
    }
}

@Composable
private fun SymbolRow(symbols: List<String>, model: KeyboardModel, keyColor: Color, textColor: Color) {
    Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        for (s in symbols) {
            SymbolKey(s, model, keyColor, textColor, Modifier.weight(1f))
        }
    }
}

/** 숫자·기호 판 공용 3행: [좌측 전환키] 。、?!ー' [⌫] — iOS numericPlane/symbolsPlane 3행과 동일
 *  구조. 좌측 키만 판마다 다르다(숫자판="#+="→기호판 진입, 기호판="123"→숫자판 진입). */
@Composable
private fun SymbolThirdRow(
    leftLabel: String, onLeft: () -> Unit,
    model: KeyboardModel, keyColor: Color, specialColor: Color, textColor: Color,
) {
    Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        SpecialKey(leftLabel, specialColor, textColor, Modifier.width(44.dp), onLeft)
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            for (s in symbolMidRow) {
                SymbolKey(s, model, keyColor, textColor, Modifier.weight(1f))
            }
        }
        SpecialKey("⌫", specialColor, textColor, Modifier.width(44.dp)) { model.tapBackspace() }
    }
}

/** 세 판(글자·숫자·기호) 공용 하단 행: [좌측 전환/복귀키][ー][🌐][space][。][enter-원형].
 *  글자판에서는 좌측이 "?123"(숫자판 진입), 숫자·기호판에서는 "한글"(글자판 복귀)만 다르고
 *  나머지 네 칸(ー·🌐·space·。·enter)은 세 판 전부 동일 — iOS backToLettersRow와 대응. */
@Composable
private fun SymbolBottomRow(
    leftLabel: String, onLeft: () -> Unit,
    model: KeyboardModel, keyColor: Color, specialColor: Color, enterColor: Color, textColor: Color,
    spaceLabel: String, onSwitchKeyboard: () -> Unit,
) {
    Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        SpecialKey(leftLabel, specialColor, textColor, Modifier.width(44.dp), onLeft)
        SpecialKey("ー", specialColor, textColor, Modifier.width(40.dp)) { model.tapSymbol("ー") }
        SpecialKey("🌐", specialColor, textColor, Modifier.width(44.dp), onSwitchKeyboard)
        SpecialKey(spaceLabel, keyColor, textColor, Modifier.weight(1f)) { model.tapSpace() }
        SpecialKey("。", specialColor, textColor, Modifier.width(40.dp)) { model.tapSymbol("。") }
        EnterKey(enterColor, textColor, Modifier.width(56.dp)) { model.tapEnter() }
    }
}

/** 특수키(⇧⌫?123🌐ー。) — Gboard 톤(specialColor) 채움의 롱프레스 변형 없는 단순 탭 키. */
@Composable
private fun SpecialKey(
    label: String, background: Color, textColor: Color,
    modifier: Modifier = Modifier, onClick: () -> Unit,
) {
    Box(
        modifier = modifier.height(47.dp)
            .background(background, RoundedCornerShape(6.dp))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = textColor, fontSize = 16.sp, textAlign = TextAlign.Center)
    }
}

/** 엔터키 — Gboard 실측대로 원형(가로 147px/세로 125px≈지름 56x48dp 스타디움) 채움 + 리턴 아이콘.
 *  기능은 기존 tapEnter 그대로, 모양만 원형으로 분리(SpecialKey는 모서리 반경 각진 사각형이라 재사용 불가). */
@Composable
private fun EnterKey(fill: Color, iconColor: Color, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(
        modifier = modifier.height(47.dp)
            .background(fill, CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text("⏎", color = iconColor, fontSize = 18.sp, textAlign = TextAlign.Center)
    }
}

/** 키캡: 탭=기본(시프트 시 변형) 라틴 전송.
 *  롱프레스는 키 종류에 따라 칸이 달라지는 팝업(슬라이드 선택, 릴리스 확정):
 *   - 쌍자음 변형 7키(ㅂㅈㄷㄱㅅㅐㅔ): [기본|변형|숫자] 3칸 — 숫자는 새로 추가된 3번째 칸.
 *   - 변형 없는 row1 키(ㅛㅕㅑ): [숫자] 1칸 — Gboard처럼 순수 숫자 롱프레스.
 *   - row2/row3(변형도 숫자도 없음): 기존과 동일하게 눌림 즉시 커밋(네이티브 키보드 감각), 롱프레스 없음. */
@Composable
private fun KeyCap(
    key: KeyDef, model: KeyboardModel, keyColor: Color, textColor: Color, digitHintColor: Color,
    modifier: Modifier, onCallout: (CalloutState?) -> Unit,
) {
    var bounds by remember { mutableStateOf(Rect.Zero) }
    Box(
        modifier = modifier.height(47.dp)
            .background(keyColor, RoundedCornerShape(6.dp))
            .onGloballyPositioned { bounds = it.boundsInParent() }
            .pointerInput(key) {
                awaitEachGesture {
                    val down = awaitFirstDown()
                    if (!key.hasVariant && key.digit == null) {
                        // 변형도 숫자 힌트도 없는 키 — 눌림 즉시 입력(네이티브 키보드 감각)
                        model.tapKey(if (model.isShifted) key.variantLatin else key.latin)
                        do {
                            val event = awaitPointerEvent()
                        } while (event.changes.any { it.pressed })
                        return@awaitEachGesture
                    }
                    val longPress = awaitLongPressOrCancellation(down.id)
                    if (longPress == null) {
                        // 롱프레스 타임아웃 전에 뗌 → 탭
                        model.tapKey(if (model.isShifted) key.variantLatin else key.latin)
                        return@awaitEachGesture
                    }
                    val cells = buildList {
                        if (key.hasVariant) {
                            add(CalloutCell.Jamo(key.label, key.latin))
                            add(CalloutCell.Jamo(key.variantLabel, key.variantLatin))
                        }
                        key.digit?.let { add(CalloutCell.Digit(it)) }
                    }
                    val state = CalloutState(key, bounds, cells, initialIndex = if (key.hasVariant) 1 else 0)
                    onCallout(state)
                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull { it.id == down.id } ?: continue
                        // 키 폭을 칸 수만큼 등분 — 손가락 x 위치가 속한 칸을 선택(팝업 칸과 좌우 일치)
                        val cellWidth = size.width.toFloat() / cells.size
                        val idx = (change.position.x / cellWidth).toInt().coerceIn(0, cells.size - 1)
                        state.selectedIndex = idx
                        if (!change.pressed) break
                    }
                    onCallout(null)
                    when (val cell = cells[state.selectedIndex]) {
                        is CalloutCell.Jamo -> model.tapKey(cell.latin)
                        is CalloutCell.Digit -> model.tapSymbol(cell.digit.toString())
                    }
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            if (model.isShifted) key.variantLabel else key.label,
            color = textColor, fontSize = 20.sp, textAlign = TextAlign.Center,
        )
        if (key.digit != null) {
            // Gboard 실측: 숫자 힌트 잉크 높이≈35px≈13dp — Text 기본 줄간격 여백을 감안해
            // fontSize를 올리고 패딩을 줄여 실측 오프셋(우상단에서 위 4dp·오른쪽 3dp)에 맞춤
            // (3라운드 실측 피드백: 13sp/4dp/3dp 조합은 잉크가 19px/12px만큼 더 안쪽에 찍힘).
            Text(
                key.digit.toString(), color = digitHintColor, fontSize = 16.sp,
                modifier = Modifier.align(Alignment.TopEnd).padding(top = 2.dp, end = 3.dp),
            )
        }
    }
}

/** 롱프레스 팝업 — 키 위 26dp, 칸 수는 state.cells 크기(1~3칸), 선택 칸 강조 */
@Composable
private fun CalloutPopup(state: CalloutState, keyColor: Color, textColor: Color) {
    val density = androidx.compose.ui.platform.LocalDensity.current
    val cellSize = 48.dp
    val cellGap = 4.dp
    val padding = 4.dp
    val totalWidth = cellSize * state.cells.size + cellGap * (state.cells.size - 1) + padding * 2
    val yOffset = with(density) { (state.keyBounds.top - 56.dp.toPx()).roundToInt() }
    val xOffset = with(density) {
        (state.keyBounds.left + state.keyBounds.width / 2 - totalWidth.toPx() / 2).roundToInt()
    }
    Row(
        Modifier
            .offset { IntOffset(xOffset.coerceAtLeast(0), yOffset.coerceAtLeast(0)) }
            .background(keyColor, RoundedCornerShape(8.dp))
            .padding(padding),
        horizontalArrangement = Arrangement.spacedBy(cellGap),
    ) {
        state.cells.forEachIndexed { index, cell ->
            val selected = index == state.selectedIndex
            Box(
                Modifier.width(cellSize).height(cellSize)
                    .background(
                        if (selected) Color(0xFF45A0FF) else Color.Transparent,
                        RoundedCornerShape(6.dp)),
                contentAlignment = Alignment.Center,
            ) {
                Text(cell.label, color = if (selected) Color.White else textColor, fontSize = 22.sp)
            }
        }
    }
}
