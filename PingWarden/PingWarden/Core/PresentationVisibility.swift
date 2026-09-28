//
//  PresentationVisibility.swift
//  PingWarden
//
//  Decides when the Dashboard may skip redrawing because nobody can see it.
//

import Foundation

enum PresentationVisibility {
    /// A window counts as visible only when some of it is on screen, it is
    /// not in the Dock, and its app is not hidden. The occlusion flag alone
    /// covers a window behind a fullscreen game or on another Space.
    static func isVisible(windowOnScreen: Bool, isMiniaturized: Bool, appIsHidden: Bool) -> Bool {
        windowOnScreen && !isMiniaturized && !appIsHidden
    }
}

/// Holds back redraws while a view is not visible and asks for exactly one
/// catch-up redraw when it becomes visible again. Data collection is not
/// gated; only the presentation work that nobody would see.
struct DeferredRefreshGate: Equatable {
    private(set) var isVisible = true
    private(set) var hasDeferredChanges = false

    /// Records a data change. Returns true when the change should be drawn
    /// now, and false when it was deferred until the view is visible.
    mutating func noteChange() -> Bool {
        guard isVisible else {
            hasDeferredChanges = true
            return false
        }
        return true
    }

    /// Records a visibility change. Returns true when the view has just
    /// become visible with changes it has not drawn yet.
    mutating func setVisible(_ visible: Bool) -> Bool {
        defer { isVisible = visible }
        guard visible, !isVisible else { return false }
        let needsRefresh = hasDeferredChanges
        hasDeferredChanges = false
        return needsRefresh
    }

    /// Returns the gate to its initial visible state, for a view that is
    /// starting over.
    mutating func reset() {
        self = DeferredRefreshGate()
    }
}
