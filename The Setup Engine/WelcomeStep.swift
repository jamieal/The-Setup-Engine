import SwiftUI

struct WelcomeStep: View {
    @EnvironmentObject var coordinator: SetupCoordinator

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "wand.and.sparkles")
                .font(.system(size: 96, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.indigo, .blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.bottom, 28)

            Text("Welcome to\nThe Setup Engine")
                .font(.system(size: 40, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)

            Text("Apps, system preferences, and personal touches —\nset up your Mac in a few minutes, no terminal required.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 40)

            featureGrid

            Spacer()

            Button {
                coordinator.next()
                Task { await coordinator.checkHomebrew() }
            } label: {
                Text("Get Started")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .padding(.bottom, 36)
        }
        .padding(.horizontal, 40)
    }

    private var featureGrid: some View {
        HStack(spacing: 24) {
            featureCard(symbol: "app.badge.checkmark", title: "Install apps", subtitle: "Pick a profile or add your own")
            featureCard(symbol: "slider.horizontal.3", title: "Tune settings", subtitle: "Dock, dark mode, Finder")
            featureCard(symbol: "checkmark.seal",      title: "Done in minutes", subtitle: "Sit back, no commands")
        }
        .frame(maxWidth: 700)
    }

    private func featureCard(symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tint)
                .frame(height: 36)

            Text(title)
                .font(.callout.weight(.semibold))

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    WelcomeStep()
        .environmentObject(SetupCoordinator())
        .frame(width: 760, height: 620)
}
