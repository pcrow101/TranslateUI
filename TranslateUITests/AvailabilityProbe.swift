//
//  AvailabilityProbe.swift
//  TranslateUITests
//
//  Temporary diagnostic — removed once end-to-end verification is done.
//

import Foundation
import Testing
import Translation

@testable import TranslateUI

@Suite("Availability probe")
struct AvailabilityProbe {
    @Test("Report installed language packs")
    func report() async {
        let service = TranslationService()
        for language in [SourceLanguage.german, .italian] {
            let status = await service.status(for: language)
            let name: String
            switch status {
            case .installed: name = "installed"
            case .supported: name = "supported (needs download)"
            case .unsupported: name = "unsupported"
            case .none: name = "nil"
            @unknown default: name = "unknown"
            }
            print("PROBE \(language.displayName) -> \(name)")
        }
    }
}
