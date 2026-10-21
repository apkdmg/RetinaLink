import Foundation
import CoreGraphics

func runViewerSessionTests() throws {
    // The failing iMac has UID 502 on the physical console while a remote
    // administrator session owns /dev/console as UID 501. Only the caller's
    // WindowServer session decides whether this Viewer can present.
    let physical:[String:Any] = [kCGSessionUserIDKey:NSNumber(value:502),
        kCGSessionOnConsoleKey:true,kCGSessionLoginDoneKey:true]
    let active = ViewerSessionState(dictionary:physical,userID:502)
    try check(active.active,"A physical Viewer session was blocked by another login")
    try check(!ViewerSessionState(dictionary:physical,userID:501).active,
              "A different user's GUI session authorized this process")
    var remote = physical; remote[kCGSessionOnConsoleKey] = false
    try check(!ViewerSessionState(dictionary:remote,userID:502).active,
              "A background or remote-only login was allowed to present")
    var signingIn = physical; signingIn[kCGSessionLoginDoneKey] = false
    try check(!ViewerSessionState(dictionary:signingIn,userID:502).active,
              "An unfinished login was treated as an active display session")
    for key in [kCGSessionOnConsoleKey,kCGSessionLoginDoneKey,kCGSessionUserIDKey] {
        var unknown = physical; unknown.removeValue(forKey:key)
        try check(!ViewerSessionState(dictionary:unknown,userID:502).active,
                  "Missing session metadata authorized presentation")
    }
    try check(!ViewerSessionState(dictionary:nil,userID:502).active,
              "A process outside a GUI session was treated as active")
    print("PASS: physical GUI session with separate remote login; background, wrong-user, incomplete and unknown sessions rejected")
}
