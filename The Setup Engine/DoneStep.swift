import SwiftUI

struct DoneStep: View {
    @EnvironmentObject var coordinator: SetupCoordinator
    @State private var animateIn = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.green.opacity(0.25), .mint.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(width: 180, height: 180)
                    .scaleEffect(animateIn ? 1 : 0.6)
                    .opacity(animateIn ? 1 : 0)

                Image(systemName: "checkmark")
                    .font(.system(size: 90, weight: .bold))
                    .foregroundStyle(.green)
                    .scaleEffect(animateIn ? 1 : 0.4)
                    .opacity(animateIn ? 1 : 0)
            }
            .padding(.bottom, 24)

            Text("Your Mac is ready")
                .font(.system(size: 38, weight: .bold))
                .padding(.bottom, 12)

            Text(summary)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 540)

            if hasInstalls {
                gatekeeperHint
                    .padding(.top, 16)
            }

            Spacer()

            HStack(spacing: 12) {
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text("Quit")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
            }
            .padding(.bottom, 36)
        }
        .padding(.horizontal, 40)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animateIn = true
            }
        }
    }

    private var hasInstalls: Bool {
        coordinator.selectedApps.contains { coordinator.itemStatuses[$0.caskName] == .succeeded }
    }

    private var gatekeeperHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("First-launch heads-up")
                    .font(.callout.weight(.semibold))
                Text("When you first open one of these apps, macOS may ask \"Are you sure you want to open it?\" That's normal — click Open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(14)
        .frame(maxWidth: 520, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var summary: String {
        let installed = coordinator.selectedApps.filter {
            coordinator.itemStatuses[$0.caskName] == .succeeded
        }.count
        let failed = coordinator.failedItems.count

        if failed == 0 {
            return installed == 0
                ? "Your settings are applied and your Mac is ready to go."
                : "We installed \(installed) \(installed == 1 ? "app" : "apps") and applied your preferences."
        } else {
            return "We installed \(installed) \(installed == 1 ? "app" : "apps") and applied your preferences. \(failed) couldn't be installed — you can try again later from the App Store or each app's website."
        }
    }
}

#Preview {
    DoneStep()
        .environmentObject(SetupCoordinator())
        .frame(width: 880, height: 620)
}
