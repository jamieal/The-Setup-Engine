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

            Text("Your apps, your Dock, your Mac — set up once, the way you like it.\nThen it's gone.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 40)

            featureGrid

            Spacer()

            Button {
                coordinator.next()
            } label: {
                Text("Get Started")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .padding(.bottom, 12)

            HStack(spacing: 18) {
                Button("Use a recipe…") { RecipeInbox.shared.chooseAndOpen() }
                    .help("Set up this Mac from a .setuprecipe file")
                Text("·").foregroundStyle(.tertiary)
                Button("Save this Mac as a recipe…") { RecipeInbox.shared.exportThisMacRequested = true }
                    .help("Record this Mac's apps, Dock and settings to set up your next Mac the same way")
            }
            .buttonStyle(.link)
            .font(.callout)
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 40)
    }

    private var featureGrid: some View {
        HStack(spacing: 24) {
            featureCard(symbol: "app.badge.checkmark", title: "Straight from the makers", subtitle: "Every app checked with Apple")
            featureCard(symbol: "person.crop.square",  title: "Yours, not a copy", subtitle: "Dock, wallpaper, folders, Touch ID")
            featureCard(symbol: "sparkles",            title: "Then it's gone", subtitle: "A receipt, undo, and no trace left")
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
