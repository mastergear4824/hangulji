// Sources/Hangulji/CandidatePanel.swift
import Cocoa

/// 자체 후보창. IMKCandidates는 사용 금지 (스펙 §2.3).
final class CandidatePanel {
    private let panel: NSPanel
    private let stack = NSStackView()

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 10),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear

        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false

        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
        ])
        panel.contentView = background
    }

    /// candidates를 표시하고 selected 행을 강조. topLeft는 화면 좌표(캐럿 아래).
    func show(candidates: [String], selected: Int, topLeft: NSPoint) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, candidate) in candidates.enumerated() {
            let label = NSTextField(labelWithString: "\(i + 1)  \(candidate)")
            label.font = .systemFont(ofSize: 16)
            label.drawsBackground = true
            label.backgroundColor = (i == selected) ? .selectedContentBackgroundColor : .clear
            label.textColor = (i == selected) ? .white : .labelColor
            stack.addArrangedSubview(label)
        }
        panel.layoutIfNeeded()
        let size = stack.fittingSize
        panel.setContentSize(NSSize(width: max(size.width, 120), height: size.height))
        panel.setFrameTopLeftPoint(topLeft)
        panel.orderFront(nil)
    }

    func hide() { panel.orderOut(nil) }
}
