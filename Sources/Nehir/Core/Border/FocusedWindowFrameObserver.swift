// SPDX-FileCopyrightText: 2026 Aleksei Gurianov and Nehir contributors
// SPDX-FileComment: Provenance=nehir-original; See=NOTICE.md
//
// SPDX-License-Identifier: GPL-2.0-only

import ApplicationServices
import CoreGraphics
import Foundation

/// Tracks the focused window's own AX move/resize notifications so focus UI can
/// follow the window while the user drags it.
///
/// WindowServer's per-window move/resize notifications (CGS events 806/807) are
/// requested with `SLSRequestNotificationsForWindows`, but they are only delivered
/// for windows owned by the calling connection. Nehir never owns the windows it
/// draws borders around, so those events never arrive for another app's window.
/// AX `moved`/`resized` notifications are emitted by the owning app and do arrive
/// cross-process, which makes them the reliable live frame source.
@MainActor
final class FocusedWindowFrameObserver {
    private static let notifications: [CFString] = [
        kAXWindowMovedNotification as CFString,
        kAXWindowResizedNotification as CFString
    ]

    /// Called at most once per main-run loop turn while notifications are
    /// arriving, with the window that produced them.
    var onFrameChange: ((_ windowId: UInt32, _ pid: pid_t) -> Void)?

    private var observer: AXObserver?
    private var element: AXUIElement?
    private var pid: pid_t = 0
    private var windowId: UInt32 = 0
    private var isUpdateScheduled = false

    /// Observes `element`, retargeting only when pid/window/element differ so
    /// repeated renders of the same focused window do not rebuild the observer.
    func track(pid: pid_t, windowId: UInt32, element: AXUIElement) {
        if self.pid == pid,
           self.windowId == windowId,
           let current = self.element,
           CFEqual(current, element)
        {
            return
        }
        stop()

        var created: AXObserver?
        guard AXObserverCreate(pid, focusedWindowFrameNotificationCallback, &created) == .success,
              let created
        else { return }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var addedNotification = false
        for name in Self.notifications where AXObserverAddNotification(created, element, name, refcon) == .success {
            addedNotification = true
        }
        guard addedNotification else { return }

        // A mouse drag runs the main run loop in event-tracking mode, so the
        // source must be registered in common modes; a default-mode source would
        // only deliver after the drag ends, which is the stale-border symptom.
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)

        observer = created
        self.element = element
        self.pid = pid
        self.windowId = windowId
    }

    func stop() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            if let element {
                for name in Self.notifications {
                    AXObserverRemoveNotification(observer, element, name)
                }
            }
        }
        observer = nil
        element = nil
        pid = 0
        windowId = 0
    }

    fileprivate func receiveNotification() {
        guard onFrameChange != nil, !isUpdateScheduled else { return }
        isUpdateScheduled = true
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isUpdateScheduled = false
                self.onFrameChange?(self.windowId, self.pid)
            }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }
}

private func focusedWindowFrameNotificationCallback(
    _: AXObserver,
    _: AXUIElement,
    _: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let frameObserver = Unmanaged<FocusedWindowFrameObserver>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated {
        frameObserver.receiveNotification()
    }
}
