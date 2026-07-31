import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController, TextOutput {
    private let model = KeyboardModel()
    private var host: UIHostingController<KeyboardView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        model.output = self
        let hostController = UIHostingController(
            rootView: KeyboardView(model: model, controller: self))
        host = hostController
        addChild(hostController)
        view.addSubview(hostController.view)
        hostController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            view.heightAnchor.constraint(equalToConstant: 300),
        ])
        hostController.didMove(toParent: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        model.commitAll()   // 포커스 이탈 시 조합 확정
        super.viewWillDisappear(animated)
    }

    // MARK: TextOutput
    func insertText(_ s: String) { textDocumentProxy.insertText(s) }
    func deleteBackward() { textDocumentProxy.deleteBackward() }
}
