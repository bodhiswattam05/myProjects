import SwiftUI

/// First launch: the privacy promise, then each permission explained in one line before
/// the system asks. Every step can be skipped.
struct OnboardingView: View {
    var onFinish: () -> Void
    @State private var page = 0

    var body: some View {
        NavigationStack {
            Group {
                if page == 0 {
                    WelcomePage { page = 1 }
                } else {
                    PermissionsPage(onFinish: onFinish)
                }
            }
            .background(CueColor.background)
        }
    }
}

private struct WelcomePage: View {
    var onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CueSpacing.xl) {
                Spacer(minLength: CueSpacing.xxl)
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundStyle(CueColor.accent)
                    .accessibilityHidden(true)
                Text("Cue")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(CueColor.primaryText)
                Text("A teleprompter that follows your voice.")
                    .font(.title3)
                    .foregroundStyle(CueColor.primaryText)
                PrivacyStatement()
                Spacer(minLength: CueSpacing.xl)
                Button(action: onContinue) {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .accessibilityIdentifier("onboarding.continue")
            }
            .padding(CueSpacing.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }
}

/// The privacy promise, shown in onboarding and Settings.
struct PrivacyStatement: View {
    var body: some View {
        VStack(alignment: .leading, spacing: CueSpacing.m) {
            Label {
                Text("Cue never sends your scripts, audio or video anywhere. iOS may download a speech model once, the same way Dictation does.")
            } icon: {
                Image(systemName: "lock")
                    .foregroundStyle(CueColor.accent)
            }
            Label {
                Text("No account, no analytics, no ads.")
            } icon: {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .foregroundStyle(CueColor.accent)
            }
        }
        .font(.body)
        .foregroundStyle(CueColor.primaryText)
    }
}

private struct PermissionsPage: View {
    var onFinish: () -> Void
    @Environment(AppServices.self) private var services

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CueSpacing.xl) {
                Text("Before you start")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(CueColor.primaryText)
                Text("Cue asks for these only when it needs them. You can change them any time in Settings.")
                    .foregroundStyle(CueColor.secondaryText)
                VStack(spacing: CueSpacing.m) {
                    ForEach(PermissionCenter.Kind.allCases) { kind in
                        PermissionRow(kind: kind, permissions: services.permissions)
                    }
                }
                Button(action: onFinish) {
                    Text("Start using Cue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .accessibilityIdentifier("onboarding.finish")
            }
            .padding(CueSpacing.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }
}

/// One permission: why it's needed, its status, and the next step.
struct PermissionRow: View {
    let kind: PermissionCenter.Kind
    let permissions: PermissionCenter

    var body: some View {
        HStack(alignment: .top, spacing: CueSpacing.m) {
            Image(systemName: kind.systemImage)
                .font(.title3)
                .foregroundStyle(CueColor.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CueSpacing.xs) {
                Text(kind.title)
                    .font(.headline)
                    .foregroundStyle(CueColor.primaryText)
                Text(kind.reason)
                    .font(.subheadline)
                    .foregroundStyle(CueColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: CueSpacing.s)
            action
        }
        .padding(CueSpacing.l)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var action: some View {
        switch permissions.status(kind) {
        case .notDetermined:
            Button("Allow") {
                Task { await permissions.request(kind) }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("permission.\(kind.rawValue)")
        case .granted:
            Label("Allowed", systemImage: "checkmark")
                .labelStyle(.iconOnly)
                .foregroundStyle(CueColor.accent)
                .accessibilityLabel(Text("Allowed"))
        case .denied:
            Button("Open Settings") { permissions.openSettings() }
                .buttonStyle(.bordered)
        }
    }
}

#Preview("Onboarding") {
    OnboardingView(onFinish: {})
        .previewEnvironment()
}
