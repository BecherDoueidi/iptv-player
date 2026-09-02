import SwiftUI
import IPTVCore

struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 48))
            Text("IPTV Player")
                .font(.title)
                .bold()
            Text(PipelineStatus.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    RootView()
}
