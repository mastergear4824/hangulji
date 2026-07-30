// scripts/make-icon.swift — 1회성: 메뉴바용 16pt 'じ' 아이콘 생성
// 실행: swift scripts/make-icon.swift
import AppKit

let size = NSSize(width: 16, height: 16)
let image = NSImage(size: size)
image.lockFocus()
NSColor.clear.setFill()
NSRect(origin: .zero, size: size).fill()
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .bold),
    .foregroundColor: NSColor.black,
]
let str = NSAttributedString(string: "じ", attributes: attrs)
let strSize = str.size()
str.draw(at: NSPoint(x: (16 - strSize.width) / 2, y: (16 - strSize.height) / 2))
image.unlockFocus()

let tiff = image.tiffRepresentation!
try! tiff.write(to: URL(fileURLWithPath: "AppBundle/main.tiff"))
print("wrote AppBundle/main.tiff (\(tiff.count) bytes)")
