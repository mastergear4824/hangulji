import SwiftUI
import UIKit
import QuartzCore

final class KeyboardViewController: UIInputViewController, TextOutput {
    private let model = KeyboardModel()
    private var host: UIHostingController<KeyboardView>?

    /// 프록시 편집 직후 도착하는 textDidChange(비동기·배칭)를 자기 편집으로 간주하는 시간 창.
    /// UITextDocumentProxy 콜백은 편집 호출과 동기적으로 오지 않으므로 플래그로는 구분 불가 —
    /// 우리 자신의 setMarkedText 등에 대한 textDidChange가 defer 리셋 이후의 나중 런루프 턴에
    /// 도착해 "외부 변경"으로 오인되면 매 키 입력마다 조합이 파기되는 치명적 회귀가 난다.
    private var lastProxyEditTime: CFTimeInterval = 0
    private static let proxyEditWindow: CFTimeInterval = 0.5

    override func viewDidLoad() {
        super.viewDidLoad()
        model.output = self
        view.backgroundColor = .clear   // 시스템 키보드 배경(블러)이 그대로 비치도록
        // SwiftUI/UIKit 타이밍 이슈 회피 — 1회만 읽어서 값으로 전달 (동적 갱신 없음)
        let hostController = UIHostingController(
            rootView: KeyboardView(model: model, controller: self,
                                    needsInputModeSwitchKey: needsInputModeSwitchKey))
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

    /// 커서 이동·필드 전환 등으로 문서가 바뀌면 호출됨. 자기 편집(TextOutput 호출) 직후
    /// proxyEditWindow 이내의 콜백은 그 편집의 반영일 뿐이므로 무시하고, 그 창을 벗어난
    /// 콜백만 "다른 곳으로 포커스가 옮겨감"으로 보고 남은 조합을 버린다(확정 아님 —
    /// commitAll을 부르면 엉뚱한 필드에 커밋되므로 절대 안 됨).
    /// 알려진 트레이드오프: 마지막 키 입력 후 0.5초 이내에 필드를 전환하면 이번 콜백에서는
    /// 파기되지 않는다 — 다음 키 입력 시 그 오래된 조합이 새 필드에 다시 마크될 수 있다.
    /// 매 키 입력마다 조합이 깨지는 치명적 회귀보다는 감수할 만한 트레이드오프.
    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        guard CACurrentMediaTime() - lastProxyEditTime > Self.proxyEditWindow else { return }
        if !model.preview.isEmpty || !model.candidates.isEmpty {
            model.discardComposition()
        }
    }

    // MARK: TextOutput
    func setMarkedText(_ s: String) {
        textDocumentProxy.setMarkedText(s, selectedRange: NSRange(location: (s as NSString).length, length: 0))
        lastProxyEditTime = CACurrentMediaTime()
    }
    func commitText(_ s: String) {
        textDocumentProxy.setMarkedText(s, selectedRange: NSRange(location: (s as NSString).length, length: 0))
        textDocumentProxy.unmarkText()
        lastProxyEditTime = CACurrentMediaTime()
    }
    func clearMarkedText() {
        textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
        textDocumentProxy.unmarkText()
        lastProxyEditTime = CACurrentMediaTime()
    }
    func insertText(_ s: String) {
        textDocumentProxy.insertText(s)
        lastProxyEditTime = CACurrentMediaTime()
    }
    func deleteBackward() {
        textDocumentProxy.deleteBackward()
        lastProxyEditTime = CACurrentMediaTime()
    }
}
