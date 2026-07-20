import SwiftUI

struct MainHeaderBannerView: View {
    var body: some View {
        Image("MainHeaderBanner")
            .resizable()
            .aspectRatio(1024.0 / 378.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

#Preview {
    MainHeaderBannerView()
}
