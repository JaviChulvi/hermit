import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "books.vertical")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hermit")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
