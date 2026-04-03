import SwiftUI

struct StreamingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .opacity(animating ? 1 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color("BackgroundSecondary"))
            .clipShape(RoundedRectangle(cornerRadius: 20))

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
        .onAppear { animating = true }
    }
}

#Preview {
    StreamingIndicator()
}
