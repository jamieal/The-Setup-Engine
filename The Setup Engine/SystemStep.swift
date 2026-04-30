import SwiftUI

struct SystemStep: View {
    @EnvironmentObject var coordinator: SetupCoordinator

    var body: some View {
        VStack(spacing: 24) {
            StepHero(
                symbol: "slider.horizontal.3",
                title: "Tune your system",
                subtitle: "Pick how you want your Mac to look and feel. You can change anything later in System Settings."
            )
            .padding(.top, 28)

            ScrollView {
                VStack(spacing: 14) {
                    appearanceCard
                    dockCard
                    finderCard
                    timeCard
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 16)
                .frame(maxWidth: 760)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Cards

    private var appearanceCard: some View {
        SettingCard(
            symbol: "paintpalette",
            title: "Appearance",
            description: "Choose a system-wide look."
        ) {
            Picker("", selection: $coordinator.settings.appearance) {
                ForEach(SystemPreferences.Appearance.allCases) { a in
                    Text(a.label).tag(a)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
        }
    }

    private var dockCard: some View {
        SettingCard(
            symbol: "dock.rectangle",
            title: "Dock",
            description: "Where the dock lives, and whether it auto-hides."
        ) {
            VStack(alignment: .trailing, spacing: 10) {
                Picker("", selection: $coordinator.settings.dockPosition) {
                    ForEach(SystemPreferences.DockPosition.allCases) { p in
                        Text(p.label).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)

                Toggle("Auto-hide", isOn: $coordinator.settings.dockAutoHide)
                    .toggleStyle(.switch)
            }
        }
    }

    private var finderCard: some View {
        SettingCard(
            symbol: "folder",
            title: "Finder",
            description: "Show the path bar; reveal hidden files."
        ) {
            VStack(alignment: .trailing, spacing: 8) {
                Toggle("Show path bar", isOn: $coordinator.settings.showPathBar)
                    .toggleStyle(.switch)
                Toggle("Show hidden files", isOn: $coordinator.settings.showHiddenFiles)
                    .toggleStyle(.switch)
            }
        }
    }

    private var timeCard: some View {
        SettingCard(
            symbol: "clock",
            title: "Time format",
            description: "24-hour time everywhere."
        ) {
            Toggle("24-hour", isOn: $coordinator.settings.twentyFourHourTime)
                .toggleStyle(.switch)
        }
    }
}

private struct SettingCard<Trailing: View>: View {
    let symbol: String
    let title: String
    let description: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            trailing()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    SystemStep()
        .environmentObject(SetupCoordinator())
        .frame(width: 880, height: 620)
}
