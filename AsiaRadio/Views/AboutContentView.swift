import SwiftUI

private enum SleepTimerSettingMode: String, CaseIterable, Identifiable {
    case scheduledTime
    case duration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scheduledTime: return "End Time"
        case .duration: return "Duration"
        }
    }
}

struct AboutContentView: View {
    @EnvironmentObject private var player: AudioPlayerService
    @EnvironmentObject private var startupChannel: StartupChannelStore
    @EnvironmentObject private var premium: PremiumManager
    @EnvironmentObject private var wakeAlarm: WakeAlarmStore

    @State private var settingMode: SleepTimerSettingMode = .duration
    @State private var selectedStopTime = Date()
    @State private var isSyncingSleepTimer = false
    @State private var hasPendingChanges = false
    @State private var sleepDays: [SleepDaySetting] = SleepDaySetting.defaults()
    @State private var selectedSleepWeekday = Calendar.current.component(.weekday, from: Date())
    @State private var wakeDays: [WakeDaySetting] = WakeDaySetting.defaults()
    @State private var selectedWakeWeekday = Calendar.current.component(.weekday, from: Date())
    @State private var wakeAlarmPending = false
    @State private var isSyncingWakeAlarm = false
    @State private var showStartupChannelRequiredAlert = false
    @State private var showWakeDayRequiredAlert = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 48))
                        .foregroundStyle(Color("AccentColor"))
                    Text(AppInfo.name)
                        .font(.title2.bold())
                    Text(AppInfo.tagline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section {
                Text("Pair Sleep Timer and Wake Radio to stop at night and start again in the morning.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Startup Channel can auto-play when you open the app (if enabled). Wake Radio auto-plays that same registered channel on the weekdays and times you set — no station pick at wake time, and no alarm screen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("What Each Setting Does")
            }

            Section {
                if premium.isPremiumUnlocked {
                    sleepTimerContent
                } else {
                    LockedPremiumFeatureView(
                        description: "Unlock sleep timer to stop playback automatically.",
                        formattedPrice: premium.formattedPrice,
                        purchaseInProgress: premium.purchaseInProgress,
                        purchaseMessage: premium.purchaseMessage,
                        onPurchase: { Task { await premium.purchase() } },
                        onRestore: { Task { await premium.restorePurchases() } },
                        onClearMessage: { premium.clearPurchaseMessage() }
                    ) {
                        sleepTimerPreview
                    }
                }
            } header: {
                premiumSectionHeader("Sleep Timer", locked: !premium.isPremiumUnlocked)
            }

            Section {
                if premium.isPremiumUnlocked {
                    wakeAlarmContent
                } else {
                    LockedPremiumFeatureView(
                        description: "Unlock Wake Radio to start your Startup Channel automatically in the morning.",
                        formattedPrice: premium.formattedPrice,
                        purchaseInProgress: premium.purchaseInProgress,
                        purchaseMessage: premium.purchaseMessage,
                        onPurchase: { Task { await premium.purchase() } },
                        onRestore: { Task { await premium.restorePurchases() } },
                        onClearMessage: { premium.clearPurchaseMessage() }
                    ) {
                        wakeAlarmPreview
                    }
                }
            } header: {
                premiumSectionHeader("Wake Radio", locked: !premium.isPremiumUnlocked)
            } footer: {
                Text("Wake Radio auto-plays your registered Startup Channel on the days and times you choose — no alarm screen. Register a Startup Channel first, turn on the weekdays you want, then tap Apply Wake Radio.")
            }

            Section {
                if premium.isPremiumUnlocked {
                    startupChannelContent
                } else {
                    LockedPremiumFeatureView(
                        description: "Register a station and play it automatically when the app opens.",
                        formattedPrice: premium.formattedPrice,
                        purchaseInProgress: premium.purchaseInProgress,
                        purchaseMessage: premium.purchaseMessage,
                        onPurchase: { Task { await premium.purchase() } },
                        onRestore: { Task { await premium.restorePurchases() } },
                        onClearMessage: { premium.clearPurchaseMessage() }
                    ) {
                        startupChannelPreview
                    }
                }
            } header: {
                premiumSectionHeader("Startup Channel", locked: !premium.isPremiumUnlocked)
            } footer: {
                Text("Turn on Use Startup Channel, then register a station from any station’s ⋯ menu. That channel can auto-play when the app opens. Wake Radio always uses the registered station at wake time (even if Use Startup Channel is off).")
            }

            Section("App Info") {
                LabeledContent("Version", value: AppInfo.version)
                LabeledContent("Supported Countries", value: AppInfo.supportedCountriesSummary)
                Text(AppInfo.copyrightLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Link(destination: AppInfo.privacyPolicyURL) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                Link(destination: AppInfo.supportURL) {
                    Label("Support", systemImage: "envelope")
                }
                Link(destination: URL(string: "mailto:\(AppInfo.supportEmail)")!) {
                    Label(AppInfo.supportEmail, systemImage: "at")
                }
            }

            Section {
                Label("Optional location services help present radio by country.", systemImage: "location")
                Text("When allowed, nearby countries appear first in Region and nearby stations first in Channels. Location is used only on this device to sort lists — it is not uploaded.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Location & Countries")
            }

            Section("How to Use") {
                Label("Tap a station to start playing.", systemImage: "hand.tap")
                Label("Use the more (⋯) menu for favorites, Startup Channel, and station info.", systemImage: "ellipsis.circle")
                Label("Location (optional): browse radio by country, with nearby countries and stations shown first.", systemImage: "location")
                Label("Startup Channel: register a station and optionally auto-play when the app opens.", systemImage: "house")
                Label("Wake Radio: on your set weekdays and times, Startup Channel starts automatically (no alarm screen). Tap Apply Wake Radio after changes.", systemImage: "radio")
                Label("While Wake Radio is on, you cannot clear or disable Startup Channel until you turn Wake Radio off.", systemImage: "lock")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Section("Legal & Acknowledgements") {
                Link(destination: AppInfo.radioBrowserURL) {
                    Label("Radio Browser", systemImage: "link")
                }
                Text("Station lists and stream URLs come from the Radio Browser open API and, when needed, official broadcaster endpoints. Broadcast audio, logos, and trademarks belong to their respective rights holders. Auradio does not claim ownership of broadcast programming. Some stations may not play due to regional restrictions or temporary outages.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(AppInfo.copyrightLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Background Playback") {
                Label("Lock screen and Control Center show the station and play/pause controls.", systemImage: "lock.fill")
                Text("Radio keeps playing when the screen is off or you leave the app. Use lock screen or Control Center to pause or resume. Fully stop from the in-app player (X).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .onAppear {
            syncFromPlayer()
            syncWakeAlarmFromStore()
        }
        .onChange(of: sleepDays) { _, _ in
            guard settingMode == .duration, !isSyncingSleepTimer else { return }
            hasPendingChanges = true
        }
        .onChange(of: selectedStopTime) { _, _ in
            guard settingMode == .scheduledTime, !isSyncingSleepTimer else { return }
            hasPendingChanges = true
        }
        .onChange(of: settingMode) { _, _ in
            guard !isSyncingSleepTimer else { return }
            hasPendingChanges = true
        }
        .onChange(of: wakeDays) { _, _ in
            guard !isSyncingWakeAlarm else { return }
            wakeAlarmPending = true
        }
        .alert("Startup Channel Required", isPresented: $showStartupChannelRequiredAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Register a Startup Channel before turning on Wake Radio. Open any station’s ⋯ menu and choose Set Startup Channel.")
        }
        .alert("Wake Day Required", isPresented: $showWakeDayRequiredAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Turn on at least one weekday before applying Wake Radio.")
        }
    }

    @ViewBuilder
    private func premiumSectionHeader(_ title: String, locked: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            if locked {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var sleepTimerContent: some View {
        Picker("Mode", selection: $settingMode) {
            ForEach(SleepTimerSettingMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)

        switch settingMode {
        case .scheduledTime:
            VStack(alignment: .leading, spacing: 6) {
                Text("End Time")
                    .font(.subheadline)

                HStack {
                    Spacer(minLength: 0)
                    DatePicker(
                        "",
                        selection: $selectedStopTime,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .datePickerStyle(.wheel)
                    .environment(\.locale, Locale(identifier: "en_US"))
                    .font(.title3.weight(.medium))
                    .frame(width: 200, height: 180)
                    .clipped()
                    Spacer(minLength: 0)
                }
            }

            Text("Playback stops automatically at the selected time. If the time has already passed today, it will stop at the same time tomorrow.")
                .font(.footnote)
                .foregroundStyle(.secondary)

        case .duration:
            Text("Sleep Days")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            sleepDayChipRow

            if let selectedIndex = sleepDays.firstIndex(where: { $0.weekday == selectedSleepWeekday }) {
                Toggle(isOn: $sleepDays[selectedIndex].isEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sleepDays[selectedIndex].shortLabel)
                            .font(.body.weight(.semibold))
                        Text(sleepDayTimeLabel(sleepDays[selectedIndex]))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if sleepDays[selectedIndex].isEnabled {
                    HStack {
                        Spacer(minLength: 0)
                        DatePicker(
                            "",
                            selection: Binding(
                                get: {
                                    Calendar.current.date(
                                        bySettingHour: sleepDays[selectedIndex].hour,
                                        minute: sleepDays[selectedIndex].minute,
                                        second: 0,
                                        of: Date()
                                    ) ?? Date()
                                },
                                set: { newValue in
                                    let calendar = Calendar.current
                                    sleepDays[selectedIndex].hour = calendar.component(.hour, from: newValue)
                                    sleepDays[selectedIndex].minute = calendar.component(.minute, from: newValue)
                                }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .datePickerStyle(.wheel)
                        .environment(\.locale, Locale(identifier: "en_US"))
                        .frame(width: 200, height: 140)
                        .clipped()
                        Spacer(minLength: 0)
                    }
                }
            }

            if let next = player.nextSleepEndDate(), settingMode == .duration, !hasPendingChanges {
                LabeledContent("Next stop", value: nextSleepLabel(next))
            }

            Text("Choose weekdays (Sun–Sat) and an end time for each day. Playback stops at that time on enabled days.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Button {
            applySleepTimer()
        } label: {
            Text("Apply")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!hasPendingChanges)

        if player.isSleepTimerActive {
            if let remaining = player.formattedSleepTimerRemaining {
                LabeledContent("Remaining", value: remaining)
            }

            if let endsAt = player.sleepTimerEndsAtTimeString {
                LabeledContent("End Time", value: endsAt)
            }

            if let mode = player.sleepTimerMode {
                LabeledContent("Mode", value: mode == .scheduledTime ? "End Time" : "Duration")
            }

            Button(role: .destructive) {
                player.cancelSleepTimer()
                syncFromPlayer()
            } label: {
                Label("Cancel Sleep Timer", systemImage: "xmark.circle")
            }
        }
    }

    private var sleepDayChipRow: some View {
        HStack(spacing: 4) {
            ForEach(sleepDays) { day in
                let selected = day.weekday == selectedSleepWeekday
                Button {
                    selectedSleepWeekday = day.weekday
                } label: {
                    Text(day.shortLabel)
                        .font(.caption2.weight(.semibold))
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                        .foregroundStyle(sleepDayChipForeground(day: day, selected: selected))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(sleepDayChipBackground(day: day, selected: selected), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.shortLabel)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private func sleepDayChipForeground(day: SleepDaySetting, selected: Bool) -> Color {
        if selected && day.isEnabled { return .white }
        if day.isEnabled { return Color("AccentColor") }
        return .secondary
    }

    private func sleepDayChipBackground(day: SleepDaySetting, selected: Bool) -> Color {
        if selected && day.isEnabled { return Color("AccentColor") }
        if day.isEnabled { return Color("AccentColor").opacity(0.18) }
        return Color(.tertiarySystemFill)
    }

    private func sleepDayTimeLabel(_ day: SleepDaySetting) -> String {
        guard day.isEnabled else { return "Off" }
        let date = Calendar.current.date(
            bySettingHour: day.hour,
            minute: day.minute,
            second: 0,
            of: Date()
        ) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func nextSleepLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d (EEE) h:mm a"
        return formatter.string(from: date)
    }

    private var sleepTimerPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Mode", selection: .constant(SleepTimerSettingMode.duration)) {
                ForEach(SleepTimerSettingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .disabled(true)

            Text("Duration — set end times by weekday")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .opacity(0.35)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var wakeAlarmContent: some View {
        Toggle("Wake Radio", isOn: Binding(
            get: { wakeAlarm.isEnabled },
            set: { enabled in
                if enabled, startupChannel.startupStation == nil {
                    showStartupChannelRequiredAlert = true
                    return
                }
                if enabled, !wakeDays.contains(where: \.isEnabled) {
                    showWakeDayRequiredAlert = true
                    return
                }
                Task {
                    if enabled {
                        await wakeAlarm.updateDays(wakeDays)
                    }
                    await wakeAlarm.setEnabled(enabled)
                    wakeAlarmPending = false
                }
            }
        ))

        if let station = startupChannel.startupStation {
            LabeledContent("Plays", value: station.name)
        } else {
            Text("No Startup Channel registered. Register one in the Startup Channel section or from a station’s ⋯ menu.")
                .font(.footnote)
                .foregroundStyle(.orange)
        }

        Text("Wake Days")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        Group {
            wakeDayChipRow

            if let selectedIndex = wakeDays.firstIndex(where: { $0.weekday == selectedWakeWeekday }) {
                Toggle(isOn: $wakeDays[selectedIndex].isEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(wakeDays[selectedIndex].shortLabel)
                            .font(.body.weight(.semibold))
                        Text(wakeDayTimeLabel(wakeDays[selectedIndex]))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if wakeDays[selectedIndex].isEnabled {
                    HStack {
                        Spacer(minLength: 0)
                        DatePicker(
                            "",
                            selection: Binding(
                                get: {
                                    Calendar.current.date(
                                        bySettingHour: wakeDays[selectedIndex].hour,
                                        minute: wakeDays[selectedIndex].minute,
                                        second: 0,
                                        of: Date()
                                    ) ?? Date()
                                },
                                set: { newValue in
                                    let calendar = Calendar.current
                                    wakeDays[selectedIndex].hour = calendar.component(.hour, from: newValue)
                                    wakeDays[selectedIndex].minute = calendar.component(.minute, from: newValue)
                                }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .datePickerStyle(.wheel)
                        .environment(\.locale, Locale(identifier: "en_US"))
                        .frame(width: 200, height: 140)
                        .clipped()
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .disabled(!wakeAlarm.isEnabled)
        .opacity(wakeAlarm.isEnabled ? 1 : 0.45)

        if !wakeAlarm.isEnabled {
            Text("Turn on Wake Radio to choose weekdays and times.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        if let next = wakeAlarm.nextFireDate, !wakeAlarmPending {
            LabeledContent("Next start", value: nextAlarmLabel(next))
        }

        if wakeAlarm.authorizationDenied {
            Text("Notifications are off. Enable them in Settings so Wake Radio can auto-start playback when the app is closed.")
                .font(.footnote)
                .foregroundStyle(.orange)
        }

        Text("Choose weekdays (Sun–Sat) and a time for each day. At that time your Startup Channel auto-plays — no alarm screen. Notifications may help start playback when the app is closed. Tap Apply Wake Radio after changes.")
            .font(.footnote)
            .foregroundStyle(.secondary)

        Button {
            guard wakeAlarm.isEnabled else { return }
            guard startupChannel.startupStation != nil else {
                showStartupChannelRequiredAlert = true
                return
            }
            guard wakeDays.contains(where: \.isEnabled) else {
                showWakeDayRequiredAlert = true
                return
            }
            Task {
                await wakeAlarm.updateDays(wakeDays)
                wakeAlarmPending = false
                syncWakeAlarmFromStore()
            }
        } label: {
            Text("Apply Wake Radio")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!wakeAlarm.isEnabled || !wakeAlarmPending)
    }

    private var wakeAlarmPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Wake Radio", isOn: .constant(false))
                .disabled(true)
            Text("Wake Days")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(WakeDaySetting.shortLabels, id: \.self) { label in
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .opacity(0.35)
        .allowsHitTesting(false)
    }

    private var wakeDayChipRow: some View {
        HStack(spacing: 4) {
            ForEach(wakeDays) { day in
                let selected = day.weekday == selectedWakeWeekday
                Button {
                    guard wakeAlarm.isEnabled else { return }
                    selectedWakeWeekday = day.weekday
                } label: {
                    Text(day.shortLabel)
                        .font(.caption2.weight(.semibold))
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                        .foregroundStyle(wakeDayChipForeground(day: day, selected: selected))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(wakeDayChipBackground(day: day, selected: selected), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!wakeAlarm.isEnabled)
                .accessibilityLabel(day.shortLabel)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private func wakeDayChipForeground(day: WakeDaySetting, selected: Bool) -> Color {
        if selected && day.isEnabled { return .white }
        if day.isEnabled { return Color("AccentColor") }
        return .secondary
    }

    private func wakeDayChipBackground(day: WakeDaySetting, selected: Bool) -> Color {
        if selected && day.isEnabled { return Color("AccentColor") }
        if day.isEnabled { return Color("AccentColor").opacity(0.18) }
        return Color(.tertiarySystemFill)
    }

    private func wakeDayTimeLabel(_ day: WakeDaySetting) -> String {
        guard day.isEnabled else { return "Off" }
        let date = Calendar.current.date(
            bySettingHour: day.hour,
            minute: day.minute,
            second: 0,
            of: Date()
        ) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func nextAlarmLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d (EEE) h:mm a"
        return formatter.string(from: date)
    }

    private func syncWakeAlarmFromStore() {
        isSyncingWakeAlarm = true
        wakeDays = WakeDaySetting.normalize(wakeAlarm.days)
        if let firstEnabled = wakeDays.first(where: \.isEnabled)?.weekday {
            selectedWakeWeekday = firstEnabled
        } else {
            selectedWakeWeekday = Calendar.current.component(.weekday, from: Date())
        }
        wakeAlarmPending = false
        DispatchQueue.main.async {
            isSyncingWakeAlarm = false
        }
    }

    @ViewBuilder
    private var startupChannelContent: some View {
        let wakeLocksStartup = wakeAlarm.isEnabled

        Toggle("Use Startup Channel", isOn: Binding(
            get: { startupChannel.isEnabled },
            set: { newValue in
                if !newValue, wakeLocksStartup { return }
                startupChannel.setEnabled(newValue)
            }
        ))
        .disabled(wakeLocksStartup && startupChannel.isEnabled)

        if let station = startupChannel.startupStation {
            LabeledContent("Registered Station", value: station.name)

            Button(role: .destructive) {
                startupChannel.clearStartupStation()
            } label: {
                Label("Clear Registered Station", systemImage: "xmark.circle")
            }
            .disabled(wakeLocksStartup)
        }

        if wakeLocksStartup {
            Text("Turn off Wake Radio before disabling or clearing Startup Channel.")
                .font(.footnote)
                .foregroundStyle(.orange)
        }

        Text("When enabled, use the station menu (⋯) to register a channel — that station can auto-play when the app opens. Wake Radio uses the same registered station at wake time. Turn off Wake Radio before clearing or disabling Startup Channel.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var startupChannelPreview: some View {
        Toggle("Use Startup Channel", isOn: .constant(false))
            .disabled(true)
            .opacity(0.35)
            .allowsHitTesting(false)
    }

    private func applySleepTimer() {
        guard premium.isPremiumUnlocked, !isSyncingSleepTimer else { return }

        switch settingMode {
        case .duration:
            player.setSleepTimerWeekly(sleepDays)
        case .scheduledTime:
            player.setSleepTimerUntil(time: selectedStopTime)
        }

        hasPendingChanges = false
        syncFromPlayer()
    }

    private func syncFromPlayer() {
        isSyncingSleepTimer = true
        defer { isSyncingSleepTimer = false }

        if let mode = player.sleepTimerMode {
            settingMode = mode == .scheduledTime ? .scheduledTime : .duration
        }

        sleepDays = SleepDaySetting.normalize(player.sleepDays)
        if let firstEnabled = sleepDays.first(where: \.isEnabled)?.weekday {
            selectedSleepWeekday = firstEnabled
        } else {
            selectedSleepWeekday = Calendar.current.component(.weekday, from: Date())
        }

        if player.isSleepTimerActive, let savedTime = player.savedSleepTimerScheduledTime {
            selectedStopTime = savedTime
        } else if settingMode == .scheduledTime {
            selectedStopTime = defaultStopTime()
        }

        hasPendingChanges = false
    }

    private func defaultStopTime() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let nextHour = min(hour + 1, 23)
        return calendar.date(bySettingHour: nextHour, minute: 0, second: 0, of: now) ?? now
    }
}

private struct LockedPremiumFeatureView<Preview: View>: View {
    let description: String
    let formattedPrice: String?
    let purchaseInProgress: Bool
    let purchaseMessage: String?
    let onPurchase: () -> Void
    let onRestore: () -> Void
    let onClearMessage: () -> Void
    @ViewBuilder let preview: () -> Preview

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            preview()

            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                Text("Premium feature")
                    .font(.subheadline.weight(.semibold))
            }

            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                onClearMessage()
                onPurchase()
            } label: {
                HStack {
                    Spacer()
                    if purchaseInProgress {
                        ProgressView()
                    } else {
                        Text(formattedPrice.map { "Get Premium · \($0)" } ?? "Get Premium")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(purchaseInProgress)

            Button("Restore Purchases") {
                onClearMessage()
                onRestore()
            }
            .font(.footnote)
            .disabled(purchaseInProgress)

            if let purchaseMessage {
                Text(purchaseMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AboutContentView()
        .environmentObject(AudioPlayerService.shared)
        .environmentObject(StartupChannelStore())
        .environmentObject(PremiumManager.shared)
        .environmentObject(WakeAlarmStore.shared)
}
