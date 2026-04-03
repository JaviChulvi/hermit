import SwiftUI

struct PrivacyBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.caption2)
            Text("On-Device")
                .font(.caption2.bold())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color("AccentColor").opacity(0.15))
        .foregroundStyle(Color("AccentColor"))
        .clipShape(Capsule())
    }
}

#Preview {
    PrivacyBadge()
}
