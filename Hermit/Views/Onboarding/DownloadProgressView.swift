import SwiftUI

enum DownloadState: Equatable {
    case notStarted
    case downloading(progress: Double)
    case completed
    case error(message: String)
}

struct DownloadProgressView: View {
    let modelName: String
    let sizeLabel: String
    let state: DownloadState
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(modelName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(sizeLabel)
                    .font(.subheadline)
                    .foregroundStyle(Color("TextSecondary"))
            }

            switch state {
            case .notStarted:
                ProgressView(value: 0, total: 1.0)
                    .tint(Color("TextSecondary"))
                Text("Waiting...")
                    .font(.caption)
                    .foregroundStyle(Color("TextSecondary"))

            case .downloading(let progress):
                ProgressView(value: progress, total: 1.0)
                    .tint(Color("AccentColor"))
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(Color("TextSecondary"))

            case .completed:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Downloaded")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

            case .error(let message):
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    if let onRetry {
                        Button("Retry", action: onRetry)
                            .font(.caption)
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding()
        .background(Color("BackgroundSecondary"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview("Not Started") {
    DownloadProgressView(
        modelName: "MiniLM-L6-v2",
        sizeLabel: "~90 MB",
        state: .notStarted
    )
    .padding()
}

#Preview("Downloading") {
    DownloadProgressView(
        modelName: "Gemma 4 E2B",
        sizeLabel: "~3.58 GB",
        state: .downloading(progress: 0.45)
    )
    .padding()
}

#Preview("Completed") {
    DownloadProgressView(
        modelName: "MiniLM-L6-v2",
        sizeLabel: "~90 MB",
        state: .completed
    )
    .padding()
}

#Preview("Error") {
    DownloadProgressView(
        modelName: "Gemma 4 E2B",
        sizeLabel: "~3.58 GB",
        state: .error(message: "Network error"),
        onRetry: {}
    )
    .padding()
}
