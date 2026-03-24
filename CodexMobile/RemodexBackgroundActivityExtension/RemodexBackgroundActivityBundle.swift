// FILE: RemodexBackgroundActivityBundle.swift
// Purpose: Registers the WidgetKit extension that renders the background connection Live Activity.
// Layer: Extension
// Exports: RemodexBackgroundActivityBundle
// Depends on: WidgetKit

import WidgetKit

@main
struct RemodexBackgroundActivityBundle: WidgetBundle {
    var body: some Widget {
        RemodexBackgroundConnectionWidget()
    }
}
