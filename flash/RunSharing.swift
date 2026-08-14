import SwiftUI

enum RunShareAction {
    case card
    case gpx

    var confirmationTitle: String {
        switch self {
        case .card: "Share this run card?"
        case .gpx: "Export this run as GPX?"
        }
    }

    var actionTitle: String {
        switch self {
        case .card: "Prepare Run Card"
        case .gpx: "Prepare GPX Export"
        }
    }

    var privacyMessage: String {
        switch self {
        case .card:
            "The card may show your route on a map along with workout stats."
        case .gpx:
            "The GPX file contains your precise route, timestamps, elevation, and available heart-rate data."
        }
    }
}

enum PreparedRunShare: Identifiable {
    case card(ShareCardDocument)
    case gpx(GPXDocument)

    var id: String {
        switch self {
        case .card: "card"
        case .gpx: "gpx"
        }
    }
}

struct RunSharingAlert: Identifiable {
    let id = UUID()
    let message: String
}

struct PreparedRunShareView: View {
    @Environment(\.dismiss) private var dismiss
    let preparedShare: PreparedRunShare

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                switch preparedShare {
                case .card(let document):
                    if let previewImage = document.previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("Preview of the run card")

                        ShareLink(
                            item: document,
                            preview: SharePreview(
                                document.filename,
                                image: Image(uiImage: previewImage)
                            )
                        ) {
                            shareButtonLabel(
                                "Open Share Sheet",
                                systemImage: "square.and.arrow.up"
                            )
                        }
                    } else {
                        Text("The run-card preview is unavailable.")
                            .foregroundStyle(.red)
                    }

                case .gpx(let document):
                    Image(systemName: "map")
                        .font(.system(size: 56))
                        .foregroundStyle(.white.opacity(0.85))
                        .accessibilityHidden(true)

                    Text(document.filename)
                        .font(Font.custom("CallingCode-Regular", size: 17))
                        .multilineTextAlignment(.center)

                    Text("Contains your precise route and available workout measurements.")
                        .font(Font.custom("CallingCode-Regular", size: 13))
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)

                    ShareLink(
                        item: document,
                        preview: SharePreview(
                            document.filename,
                            icon: Image(systemName: "map")
                        )
                    ) {
                        shareButtonLabel("Open Share Sheet", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.flashBackground.ignoresSafeArea())
            .foregroundStyle(.white)
            .navigationTitle("Ready to Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func shareButtonLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(Font.custom("CallingCode-Regular", size: 18))
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.white.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
