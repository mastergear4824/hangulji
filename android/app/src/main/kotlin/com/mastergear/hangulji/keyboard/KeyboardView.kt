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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
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

/** 키 정의: 표시 자모·전송 라틴 + 시프트/롱프레스 변형 (변형 없으면 base와 동일) */
private data class KeyDef(
    val label: String, val latin: Char,
    val variantLabel: String, val variantLatin: Char,
) {
    val hasVariant: Boolean get() = latin != variantLatin
}

private val row1 = listOf(
    KeyDef("ㅂ", 'q', "ㅃ", 'Q'), KeyDef("ㅈ", 'w', "ㅉ", 'W'), KeyDef("ㄷ", 'e', "ㄸ", 'E'),
    KeyDef("ㄱ", 'r', "ㄲ", 'R'), KeyDef("ㅅ", 't', "ㅆ", 'T'), KeyDef("ㅛ", 'y', "ㅛ", 'y'),
    KeyDef("ㅕ", 'u', "ㅕ", 'u'), KeyDef("ㅑ", 'i', "ㅑ", 'i'), KeyDef("ㅐ", 'o', "ㅒ", 'O'),
    KeyDef("ㅔ", 'p', "ㅖ", 'P'),
)
private val row2 = "ㅁㄴㅇㄹㅎㅗㅓㅏㅣ".zip("asdfghjkl")
    .map { (label, latin) -> KeyDef(label.toString(), latin, label.toString(), latin) }
private val row3 = "ㅋㅌㅊㅍㅠㅜㅡ".zip("zxcvbnm")
    .map { (label, latin) -> KeyDef(label.toString(), latin, label.toString(), latin) }

/** 롱프레스 팝업 상태 — 동시에 하나만 존재 */
private class CalloutState(val key: KeyDef, val keyBounds: Rect) {
    var variantSelected by mutableStateOf(true)   // 팝업이 뜨는 순간엔 변형 칸 선택
}

@Composable
fun KeyboardScreen(model: KeyboardModel, onSwitchKeyboard: () -> Unit) {
    val dark = isSystemInDarkTheme()
    val background = if (dark) Color(0xFF2B2B2B) else Color(0xFFD1D4DA)
    val keyColor = if (dark) Color(0xFF6B6B6B) else Color.White
    val specialColor = if (dark) Color(0xFF474747) else Color(0xFFADB3BD)
    val textColor = if (dark) Color.White else Color.Black
    var callout by remember { mutableStateOf<CalloutState?>(null) }

    Box {
        Column(
            modifier = Modifier.fillMaxWidth().background(background).padding(3.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            CandidateBar(model, keyColor, textColor)
            KeyRow(row1, model, keyColor, textColor, onCallout = { callout = it })
            KeyRow(row2, model, keyColor, textColor, onCallout = { callout = it })
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                SpecialKey(if (model.isShifted) "⬆" else "⇧", specialColor, textColor,
                    Modifier.width(44.dp)) { model.toggleShift() }
                Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    for (key in row3) {
                        KeyCap(key, model, keyColor, textColor, Modifier.weight(1f),
                            onCallout = { callout = it })
                    }
                }
                SpecialKey("⌫", specialColor, textColor, Modifier.width(44.dp)) {
                    model.tapBackspace()
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                SpecialKey("🌐", specialColor, textColor, Modifier.width(44.dp), onSwitchKeyboard)
                SpecialKey("ー", specialColor, textColor, Modifier.width(40.dp)) {
                    model.tapSymbol("ー")
                }
                SpecialKey(
                    if (model.candidates.isEmpty()) "변환·스페이스" else "다음 후보",
                    keyColor, textColor, Modifier.weight(1f)) { model.tapSpace() }
                SpecialKey("。", specialColor, textColor, Modifier.width(40.dp)) {
                    model.tapSymbol("。")
                }
                SpecialKey("⏎", specialColor, textColor, Modifier.width(44.dp)) {
                    model.tapEnter()
                }
            }
        }
        callout?.let { CalloutPopup(it, keyColor, textColor) }
    }
}

@Composable
private fun CandidateBar(model: KeyboardModel, keyColor: Color, textColor: Color) {
    Box(
        Modifier.fillMaxWidth().height(44.dp)
            .background(keyColor, RoundedCornerShape(6.dp)),
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
    keys: List<KeyDef>, model: KeyboardModel, keyColor: Color, textColor: Color,
    onCallout: (CalloutState?) -> Unit,
) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        for (key in keys) {
            KeyCap(key, model, keyColor, textColor, Modifier.weight(1f), onCallout)
        }
    }
}

/** 특수키(⇧⌫🌐ー변환·스페이스。⏎) — 롱프레스 변형 없는 단순 탭 키. 브리프 문서에 시그니처만
 *  암시되어 있어(호출부 5개 인자: 라벨·배경색·글자색·Modifier·onClick) KeyCap과 동일한 스타일로 보강. */
@Composable
private fun SpecialKey(
    label: String, background: Color, textColor: Color,
    modifier: Modifier = Modifier, onClick: () -> Unit,
) {
    Box(
        modifier = modifier.height(43.dp)
            .background(background, RoundedCornerShape(5.dp))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = textColor, fontSize = 16.sp, textAlign = TextAlign.Center)
    }
}

/** 키캡: 탭=기본(시프트 시 변형) 라틴 전송, 변형 키 롱프레스=두 칸 팝업(슬라이드 선택, 릴리스 확정) */
@Composable
private fun KeyCap(
    key: KeyDef, model: KeyboardModel, keyColor: Color, textColor: Color,
    modifier: Modifier, onCallout: (CalloutState?) -> Unit,
) {
    var bounds by remember { mutableStateOf(Rect.Zero) }
    Box(
        modifier = modifier.height(43.dp)
            .background(keyColor, RoundedCornerShape(5.dp))
            .onGloballyPositioned { bounds = it.boundsInParent() }
            .pointerInput(key) {
                awaitEachGesture {
                    val down = awaitFirstDown()
                    if (!key.hasVariant) {
                        // 변형 없는 키 — 눌림 즉시 입력(네이티브 키보드 감각)
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
                    val state = CalloutState(key, bounds)
                    onCallout(state)
                    var selectVariant = true
                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull { it.id == down.id } ?: continue
                        // 키 중심 기준 좌=기본, 우=변형 (팝업 두 칸과 좌우 일치)
                        selectVariant = change.position.x >= size.width / 2f
                        state.variantSelected = selectVariant
                        if (!change.pressed) break
                    }
                    onCallout(null)
                    model.tapKey(if (selectVariant) key.variantLatin else key.latin)
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            if (model.isShifted) key.variantLabel else key.label,
            color = textColor, fontSize = 20.sp, textAlign = TextAlign.Center,
        )
    }
}

/** 롱프레스 두 칸 팝업 — 키 위 26dp, [기본|변형], 선택 칸 강조 */
@Composable
private fun CalloutPopup(state: CalloutState, keyColor: Color, textColor: Color) {
    val density = androidx.compose.ui.platform.LocalDensity.current
    val yOffset = with(density) { (state.keyBounds.top - 56.dp.toPx()).roundToInt() }
    val xOffset = with(density) {
        (state.keyBounds.left + state.keyBounds.width / 2 - 55.dp.toPx()).roundToInt()
    }
    Row(
        Modifier
            .offset { IntOffset(xOffset.coerceAtLeast(0), yOffset.coerceAtLeast(0)) }
            .background(keyColor, RoundedCornerShape(8.dp))
            .padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        for ((label, selected) in listOf(
            state.key.label to !state.variantSelected,
            state.key.variantLabel to state.variantSelected,
        )) {
            Box(
                Modifier.width(48.dp).height(48.dp)
                    .background(
                        if (selected) Color(0xFF45A0FF) else Color.Transparent,
                        RoundedCornerShape(6.dp)),
                contentAlignment = Alignment.Center,
            ) {
                Text(label, color = if (selected) Color.White else textColor, fontSize = 22.sp)
            }
        }
    }
}
