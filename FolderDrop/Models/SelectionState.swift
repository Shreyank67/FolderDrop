//
//  SelectionState.swift
//  FolderDrop
//
//  Finder-style multi-selection over a single displayed list of FolderEntry values.
//  A plain value type: no callbacks, no side effects — just old state + an intent in,
//  new state out. Owned by ContentView the same way selectedEntry used to be.
//

import Foundation

struct SelectionState: Equatable {
    /// Persistent selection built up by plain clicks (replaces) and Command-clicks
    /// (adds/removes one at a time). Never touched directly by Shift operations.
    private(set) var committedEntries: Set<FolderEntry> = []
    /// The live Shift range (anchor...active), reassigned from scratch on every
    /// Shift action so it can grow or shrink freely, with nothing left behind.
    private(set) var shiftRangeEntries: Set<FolderEntry> = []
    private(set) var activeEntry: FolderEntry?
    private(set) var selectionAnchor: FolderEntry?

    /// What callers actually see: Command-created selections plus whatever the
    /// live Shift range currently spans.
    var selectedEntries: Set<FolderEntry> { committedEntries.union(shiftRangeEntries) }

    /// Plain click: select only this entry, and it becomes both the active entry
    /// and the anchor for any future shift-click/shift-arrow range. This is a full
    /// reset — any prior Command selection or live Shift range is discarded.
    mutating func selectOnly(_ entry: FolderEntry) {
        committedEntries = [entry]
        shiftRangeEntries = []
        activeEntry = entry
        selectionAnchor = entry
    }

    /// Command-click: flip this entry's membership without touching the rest of
    /// the persistent selection. It always becomes the active entry and the new
    /// anchor, whether it ended up selected or deselected. Any live Shift range is
    /// folded into the persistent selection first, so starting a new range from
    /// this item doesn't lose what Shift had already covered.
    mutating func toggle(_ entry: FolderEntry) {
        commitShiftRange()

        if committedEntries.contains(entry) {
            committedEntries.remove(entry)
        } else {
            committedEntries.insert(entry)
        }
        activeEntry = entry
        selectionAnchor = entry
    }

    /// Shift-click/shift-arrow: select every entry between the anchor and the
    /// target (inclusive), recomputed fresh each time so the range can grow or
    /// shrink as the target moves — the anchor itself never moves, and this never
    /// touches committedEntries, so independently Command-selected items persist.
    mutating func selectRange(to entry: FolderEntry, in entries: [FolderEntry]) {
        let anchor = selectionAnchor ?? entry

        guard let anchorIndex = entries.firstIndex(of: anchor),
              let targetIndex = entries.firstIndex(of: entry) else {
            selectOnly(entry)
            return
        }

        let range = anchorIndex <= targetIndex ? anchorIndex...targetIndex : targetIndex...anchorIndex
        shiftRangeEntries = Set(entries[range])
        selectionAnchor = anchor
        activeEntry = entry
    }

    private mutating func commitShiftRange() {
        guard !shiftRangeEntries.isEmpty else { return }
        committedEntries.formUnion(shiftRangeEntries)
        shiftRangeEntries = []
    }

    /// Arrow key: move the active entry by one position within entries.
    /// Without extending, this collapses to a single selection at the new
    /// position. With extending (Shift held), it grows/shrinks the range
    /// between the fixed anchor and the new active position.
    mutating func moveActive(by offset: Int, in entries: [FolderEntry], extending: Bool) {
        guard !entries.isEmpty else { return }

        guard let active = activeEntry, let currentIndex = entries.firstIndex(of: active) else {
            if let first = entries.first {
                selectOnly(first)
            }
            return
        }

        let nextIndex = currentIndex + offset
        guard entries.indices.contains(nextIndex) else { return }
        let nextEntry = entries[nextIndex]

        if extending {
            selectRange(to: nextEntry, in: entries)
        } else {
            selectOnly(nextEntry)
        }
    }

    mutating func clear() {
        committedEntries = []
        shiftRangeEntries = []
        activeEntry = nil
        selectionAnchor = nil
    }
}
