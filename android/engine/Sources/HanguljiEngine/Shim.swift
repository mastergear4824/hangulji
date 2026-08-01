// Shim.swift — @_cdecl C ABI. JNI 글루(android/app/src/main/cpp/hangulji_jni.c)가 호출한다.
//
// 왜 HanguljiConversion(KanjiConverter.swift)을 그대로 링크하지 않는가:
// 그쪽은 KanaKanjiConverterModuleWithDefaultDictionary의 Bundle.module 리소스로 사전을
// 찾는데, APK 안에서는 SPM 리소스 번들 경로가 존재하지 않는다. Android에서는 사전
// 디렉터리를 명시 경로로 받고(assets→filesDir 복사본), 후보 목록 계약(한자 max개 +
// 가나·가타카나 폴백, 순서 유지, 중복 제거)만 KanjiConverter.swift와 동일하게 유지한다.
// pre-1.0 API 변동은 이 파일 한 곳에 가둔다 — 시그니처가 어긋나면 이 파일만 고친다.
import Foundation
import HanguljiCore
import KanaKanjiConverterModule

private final class EngineBox {
    let converter: KanaKanjiConverter
    let scratchDirectory: URL

    init(dictionaryPath: String) {
        self.converter = KanaKanjiConverter(
            dictionaryURL: URL(fileURLWithPath: dictionaryPath, isDirectory: true),
            preloadDictionary: true
        )
        self.scratchDirectory = FileManager.default.temporaryDirectory
    }

    func candidateList(for reading: String, max: Int) -> [String] {
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)

        let options = ConvertRequestOptions(
            N_best: max,
            requireJapanesePrediction: false,
            requireEnglishPrediction: false,
            keyboardLanguage: .ja_JP,
            learningType: .nothing,
            memoryDirectoryURL: scratchDirectory,
            sharedContainerURL: scratchDirectory,
            textReplacer: .empty,   // 이모지 사전은 번들 리소스라 Android에선 미사용
            specialCandidateProviders: KanaKanjiConverter.defaultSpecialCandidateProviders,
            metadata: nil
        )
        let results = converter.requestCandidates(composing, options: options)

        var seen = Set<String>()
        var kanji: [String] = []
        for text in results.mainResults.map(\.text) {
            if seen.insert(text).inserted { kanji.append(text) }
        }
        var list = Array(kanji.prefix(max))
        for fallback in [reading, reading.toKatakana()] where !list.contains(fallback) {
            list.append(fallback)
        }
        return list
    }
}

@_cdecl("hangulji_converter_init")
public func hangulji_converter_init(
    _ dictionaryPath: UnsafePointer<CChar>?
) -> UnsafeMutableRawPointer? {
    guard let dictionaryPath, let path = String(validatingCString: dictionaryPath),
          FileManager.default.fileExists(atPath: path) else { return nil }
    let box = EngineBox(dictionaryPath: path)
    return Unmanaged.passRetained(box).toOpaque()
}

@_cdecl("hangulji_converter_convert")
public func hangulji_converter_convert(
    _ handle: UnsafeMutableRawPointer?,
    _ reading: UnsafePointer<CChar>?,
    _ maxCandidates: Int32
) -> UnsafeMutablePointer<CChar>? {
    guard let handle, let reading,
          let readingString = String(validatingCString: reading) else { return nil }
    let box = Unmanaged<EngineBox>.fromOpaque(handle).takeUnretainedValue()
    let list = box.candidateList(for: readingString, max: Int(maxCandidates))
    return strdup(list.joined(separator: "\n"))
}

@_cdecl("hangulji_string_free")
public func hangulji_string_free(_ str: UnsafeMutablePointer<CChar>?) {
    free(str)
}

@_cdecl("hangulji_converter_free")
public func hangulji_converter_free(_ handle: UnsafeMutableRawPointer?) {
    guard let handle else { return }
    Unmanaged<EngineBox>.fromOpaque(handle).release()
}
