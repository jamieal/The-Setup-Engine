import SwiftUI

struct ProfileStep: View {
    @EnvironmentObject var coordinator: SetupCoordinator

    var body: some View {
        VStack(spacing: 24) {
            StepHero(
                symbol: "person.crop.circle.badge.checkmark",
                title: "Pick a profile",
                subtitle: "Each profile is a curated set of apps. You can fine-tune them on the next step."
            )
            .padding(.top, 28)

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 320, maximum: 380), spacing: 16)],
                    spacing: 16
                ) {
                    ForEach(Suggestions.profiles) { profile in
                        ProfileCard(
                            profile: profile,
                            isSelected: coordinator.selectedProfile?.id == profile.id,
                            onTap: { coordinator.apply(profile: profile) }
                        )
                    }
                    customCard
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 24)
            }
        }
    }

    private var customCard: some View {
        Button {
            coordinator.selectedProfile = nil
            coordinator.next()
        } label: {
            cardShell(stroke: Color.secondary.opacity(0.15), strokeWidth: 1) {
                cardHeader(
                    symbol: "plus.app",
                    gradient: [.gray, .secondary],
                    title: "Custom",
                    subtitle: "Start from scratch",
                    showCheck: false
                )
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileCard: View {
    let profile: SetupProfile
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            cardShell(
                stroke: isSelected ? Color.accentColor : Color.secondary.opacity(0.15),
                strokeWidth: isSelected ? 2 : 1
            ) {
                cardHeader(
                    symbol: profile.icon,
                    gradient: gradient,
                    title: profile.name,
                    subtitle: profile.description,
                    showCheck: isSelected
                )

                HStack(spacing: 10) {
                    ForEach(profile.casks.prefix(7)) { app in
                        CaskIconView(
                            homepageURL: app.homepageURL,
                            caskName: app.caskName,
                            showSubscriptionBadge: false
                        )
                            .frame(width: 36, height: 36)
                            .help(app.displayName)
                    }
                    if profile.casks.count > 7 {
                        Text("+\(profile.casks.count - 7)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var gradient: [Color] {
        switch profile.name {
        case "Developer": [.indigo, .purple]
        case "Designer":  [.pink, .orange]
        case "Office":    [.teal, .blue]
        case "Media":     [.red, .pink]
        default:          [.gray, .secondary]
        }
    }
}

// MARK: - Shared chrome

@ViewBuilder
private func cardShell<Content: View>(
    stroke: Color,
    strokeWidth: CGFloat,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 18) {
        content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
    .frame(minHeight: 160)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    .overlay(
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(stroke, lineWidth: strokeWidth)
    )
}

private func cardHeader(
    symbol: String,
    gradient: [Color],
    title: String,
    subtitle: String,
    showCheck: Bool
) -> some View {
    HStack(spacing: 14) {
        Image(systemName: symbol)
            .font(.title2)
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(
                LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 10)
            )
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        Spacer(minLength: 0)
        if showCheck {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
        }
    }
}

#Preview {
    ProfileStep()
        .environmentObject(SetupCoordinator())
        .frame(width: 980, height: 720)
}
