import Foundation
import CoreGraphics

// /dev/console ownership can follow a separate Screen Sharing login. Ask
// WindowServer about this process's GUI session instead of that global file.
struct ViewerSessionState {
    let userID: UInt32?
    let onConsole: Bool?
    let loginDone: Bool?
    let expectedUserID: UInt32

    init(dictionary: [String:Any]?, userID: UInt32) {
        self.userID = (dictionary?[kCGSessionUserIDKey] as? NSNumber)?.uint32Value
        onConsole = dictionary?[kCGSessionOnConsoleKey] as? Bool
        loginDone = dictionary?[kCGSessionLoginDoneKey] as? Bool
        expectedUserID = userID
    }
    static var current: ViewerSessionState {
        ViewerSessionState(dictionary:CGSessionCopyCurrentDictionary() as? [String:Any],userID:getuid())
    }
    var active: Bool { userID == expectedUserID && onConsole == true && loginDone == true }
    var metadata: [String:Any] {
        var result:[String:Any] = ["source":"window-server-session","active":active,"processUserID":expectedUserID]
        if let userID = userID { result["sessionUserID"] = userID }
        if let onConsole = onConsole { result["onConsole"] = onConsole }
        if let loginDone = loginDone { result["loginDone"] = loginDone }
        return result
    }
}
