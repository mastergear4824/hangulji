import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController, TextOutput {
    private let model = KeyboardModel()
    private var host: UIHostingController<KeyboardView>?

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

    // MARK: TextOutput
    func setMarkedText(_ s: String) {
        textDocumentProxy.setMarkedText(s, selectedRange: NSRange(location: (s as NSString).length, length: 0))
    }
    func commitText(_ s: String) {
        textDocumentProxy.setMarkedText(s, selectedRange: NSRange(location: (s as NSString).length, length: 0))
        textDocumentProxy.unmarkText()
    }
    func clearMarkedText() {
        textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
        textDocumentProxy.unmarkText()
    }
    func insertText(_ s: String) { textDocumentProxy.insertText(s) }
    func deleteBackward() { textDocumentProxy.deleteBackward() }
}
