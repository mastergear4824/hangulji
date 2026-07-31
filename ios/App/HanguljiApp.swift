import SwiftUI
import UIKit

@main
struct HanguljiApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var testInput = ""

    var body: some View {
        NavigationStack {
            List {
                Section("설치") {
                    Text("설정 → 일반 → 키보드 → 키보드 → 새로운 키보드 추가 → **한글지**")
                    Text("입력창에서 지구본 키를 길게 눌러 한글지로 전환")
                }
                Section("테스트") {
                    TextField("여기서 타이핑 테스트 (토우쿄우 → 変換 → 東京)", text: $testInput)
                }
                Section("입력 규칙 요약") {
                    Text("카=か 가=が (위치 무관) · 받침ㅅ=っ · 받침ㄴ=ん · 장음은 철자대로(토우쿄우) · を=워 は=하")
                }
            }
            .navigationTitle("한글지")
        }
        // 실측 검증용 — 키보드가 실제로 화면에 뜰 때 시스템이 보고하는 프레임 높이를 콘솔에 남긴다.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            if let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
                NSLog("HanguljiApp KBFrame height=%.1f", frame.height)
            }
        }
    }
}
