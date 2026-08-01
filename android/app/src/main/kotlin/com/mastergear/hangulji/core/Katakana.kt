package com.mastergear.hangulji.core

/** 히라가나(U+3041–U+3096)를 가타카나(+0x60)로. 그 외 문자는 보존. (전 범위 BMP — Char 단위 안전) */
fun String.toKatakana(): String = buildString(length) {
    for (ch in this@toKatakana) {
        append(if (ch.code in 0x3041..0x3096) (ch.code + 0x60).toChar() else ch)
    }
}
