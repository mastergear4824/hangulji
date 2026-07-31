// ios/Keyboard/GlobeButton.swift
import SwiftUI
import UIKit

/// 키보드 전환 키 — handleInputModeList는 UIKit 타깃-액션이 필요해 래핑
struct GlobeButton: UIViewRepresentable {
    weak var controller: UIInputViewController?

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        let configuration = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        button.setImage(UIImage(systemName: "globe", withConfiguration: configuration), for: .normal)
        button.tintColor = .label   // 액센트(블루) 금지 — 시스템 키보드 톤에 맞춤
        button.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 0.28, alpha: 1)
                : UIColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1)
        }
        button.layer.cornerRadius = 4.6
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.35
        button.layer.shadowRadius = 0
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        if let controller {
            button.addTarget(controller,
                             action: #selector(UIInputViewController.handleInputModeList(from:with:)),
                             for: .allTouchEvents)
        }
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}
}
