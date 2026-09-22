// The walkthrough on screen: one overlay over the window, with every word
// taken from the published journey so a definition changed through Echo
// changes what is read here without a release of this app.

import SwiftUI
import WisentDesignSystem
import WisentOnboarding

/// on screen. The identifier keys are the fallback, not the copy.
struct GlinaOnboardingOverlay: View {
    let screen: JourneyScreen?
    let errorMessage: String?
    let isWorking: Bool
    let isFinalScreen: Bool
    let stepNumber: Int?
    let advance: () -> Void
    let importAsset: () -> Void
    let retry: () -> Void

    var body: some View {
        ZStack {
            WisentDesign.canvas.opacity(0.94)
                .ignoresSafeArea()

            WisentPanel(padding: WisentDesign.Space.x6) {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x5) {
                    HStack(spacing: WisentDesign.Space.x3) {
                        Text("GLINA")
                            .font(WisentTypeScale.eyebrow())
                            .tracking(0.7)
                            .foregroundStyle(WisentDesign.brand)
                        Spacer()
                        if let stepNumber {
                            WisentBadge("Step \(stepNumber) of 3", symbol: "sparkles", tone: .brand)
                        }
                    }

                    VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                        Text(title)
                            .font(WisentTypography.display(28))
                            .foregroundStyle(WisentDesign.ink)
                        Text(explanation)
                            .font(WisentTypography.body(15))
                            .foregroundStyle(WisentDesign.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(WisentTypeScale.bodyStrong())
                            .foregroundStyle(WisentDesign.danger)
                    }

                    HStack {
                        Spacer()
                        if screen == nil {
                            Button("Try Again", action: retry)
                                .buttonStyle(WisentPrimaryButtonStyle())
                                .disabled(isWorking)
                        } else if isFinalScreen {
                            Button("Import GLB…", action: importAsset)
                                .buttonStyle(WisentPrimaryButtonStyle())
                                .keyboardShortcut(.defaultAction)
                                .disabled(isWorking)
                        } else {
                            Button("Continue", action: advance)
                                .buttonStyle(WisentPrimaryButtonStyle())
                                .keyboardShortcut(.defaultAction)
                                .disabled(isWorking)
                        }
                    }
                }
            }
            .frame(width: 620)
            .padding(WisentDesign.Space.x8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Glina first-run walkthrough")
    }

    private var title: String {
        screen?.presentation.text("title")
            ?? screen?.titleKey
            ?? "First-run walkthrough unavailable"
    }

    private var explanation: String {
        screen?.presentation.text("body")
            ?? screen?.bodyKey
            ?? "The bundled walkthrough could not be loaded. Nothing about your pipeline or credentials has changed."
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func text(_ key: String) -> String? {
        guard case let .string(value)? = self[key] else { return nil }
        return value
    }
}
