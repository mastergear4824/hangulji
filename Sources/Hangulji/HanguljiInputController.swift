// Sources/Hangulji/HanguljiInputController.swift
import Cocoa
import InputMethodKit

/// @objc 이름을 고정해 Info.plist의 InputMethodServerControllerClass에서
/// 모듈 접두사 없이 찾을 수 있게 한다.
@objc(HanguljiInputController)
public class HanguljiInputController: IMKInputController {
    public override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        return false  // Task 8에서 구현
    }
}
