import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController, TextOutput {
    private let model = KeyboardModel()
    private var host: UIHostingController<KeyboardView>?

    /// TextOutput 메서드가 textDocumentProxy를 편집하는 동안만 true — textDidChange가
    /// 그 편집을 "외부에서 필드가 바뀜"으로 오인해 조합을 버리지 않도록 구분한다.
    private var isProxyEdit = false

    override func viewDidLoad() {
        super.viewDidLoad()
        model.output = self
        view.backgroundColor = .clear   // 시스템 키보드 배경(블러)이 그대로 비치도록
        let hostController = UIHostingController(
            rootView: KeyboardView(model: model, controller: self))
        host = hostController
        hostController.view.backgroundColor = .clear
        addChild(hostController)
        view.addSubview(hostController.view)
        hostController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            view.heightAnchor.constraint(equalToConstant: 260),
        ])
        hostController.didMove(toParent: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        model.commitAll()   // 포커스 이탈 시 조합 확정
        super.viewWillDisappear(animated)
    }

    /// 커서 이동·필드 전환 등으로 문서가 바뀌면 호출됨. 우리 자신의 TextOutput 호출로 인한
    /// 변경(isProxyEdit)이 아니라면 — 다른 곳으로 포커스가 옮겨간 것이므로 남은 조합을 버린다
    /// (그 텍스트를 확정하면 엉뚱한 필드에 커밋되므로 절대 commitAll을 부르면 안 됨).
    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        guard !isProxyEdit else { return }
        if !model.preview.isEmpty || !model.candidates.isEmpty {
            model.discardComposition()
        }
    }

    // MARK: TextOutput
    func setMarkedText(_ s: String) {
        isProxyEdit = true
        defer { isProxyEdit = false }
        textDocumentProxy.setMarkedText(s, selectedRange: NSRange(location: (s as NSString).length, length: 0))
    }
    func commitText(_ s: String) {
        isProxyEdit = true
        defer { isProxyEdit = false }
        textDocumentProxy.setMarkedText(s, selectedRange: NSRange(location: (s as NSString).length, length: 0))
        textDocumentProxy.unmarkText()
    }
    func clearMarkedText() {
        isProxyEdit = true
        defer { isProxyEdit = false }
        textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
        textDocumentProxy.unmarkText()
    }
    func insertText(_ s: String) {
        isProxyEdit = true
        defer { isProxyEdit = false }
        textDocumentProxy.insertText(s)
    }
    func deleteBackward() {
        isProxyEdit = true
        defer { isProxyEdit = false }
        textDocumentProxy.deleteBackward()
    }
}
