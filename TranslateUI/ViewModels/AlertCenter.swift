//
//  AlertCenter.swift
//  TranslateUI
//

import Foundation
import Observation

/// The list of actionable pipeline problems shown as banners.
///
/// Alerts are keyed by `PipelineAlert.ID`, so re-posting the same kind of
/// problem updates the existing banner instead of stacking duplicates — the
/// pipeline can report "translations failed" once per language pass without
/// burying the screenshot under identical rows.
@MainActor
@Observable
final class AlertCenter {
    private(set) var alerts: [PipelineAlert] = []

    var isEmpty: Bool { alerts.isEmpty }

    func post(_ alert: PipelineAlert) {
        if let index = alerts.firstIndex(where: { $0.id == alert.id }) {
            alerts[index] = alert
        } else {
            alerts.append(alert)
        }
    }

    func dismiss(_ alert: PipelineAlert) {
        dismiss(id: alert.id)
    }

    func dismiss(id: PipelineAlert.ID) {
        alerts.removeAll { $0.id == id }
    }

    func contains(id: PipelineAlert.ID) -> Bool {
        alerts.contains { $0.id == id }
    }

    func removeAll() {
        alerts.removeAll()
    }
}
