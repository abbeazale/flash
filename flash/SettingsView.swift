import SwiftData
import SwiftUI

enum RunnerProfileDraftError: LocalizedError, Equatable {
    case maxHRMustBeWholeNumber
    case restingHRMustBeWholeNumber

    var errorDescription: String? {
        switch self {
        case .maxHRMustBeWholeNumber:
            "Maximum heart rate must be a whole number."
        case .restingHRMustBeWholeNumber:
            "Resting heart rate must be a whole number."
        }
    }
}

struct RunnerProfileDraft {
    var maxHRText = ""
    var restingHRText = ""
    var includesBirthdate = false
    var birthdate = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    var trimpSex = TRIMPSex.notSet
    var distanceUnit = PreferredDistanceUnit.kilometers

    init() {}

    init(profile: RunnerProfile) {
        maxHRText = profile.maxHR.map(String.init) ?? ""
        restingHRText = profile.restingHR.map(String.init) ?? ""
        includesBirthdate = profile.birthdate != nil
        birthdate = profile.birthdate
            ?? Calendar.current.date(byAdding: .year, value: -30, to: Date())
            ?? Date()
        trimpSex = profile.trimpSex
        distanceUnit = profile.distanceUnit
    }

    func validatedValues(on date: Date = Date(), calendar: Calendar = .current) throws -> RunnerProfileValues {
        let maxHR = try parseOptionalHeartRate(
            maxHRText,
            invalidError: .maxHRMustBeWholeNumber
        )
        let restingHR = try parseOptionalHeartRate(
            restingHRText,
            invalidError: .restingHRMustBeWholeNumber
        )
        let selectedBirthdate = includesBirthdate ? birthdate : nil

        try RunnerProfile.validate(
            maxHR: maxHR,
            restingHR: restingHR,
            birthdate: selectedBirthdate,
            on: date,
            calendar: calendar
        )

        return RunnerProfileValues(
            maxHR: maxHR,
            restingHR: restingHR,
            birthdate: selectedBirthdate,
            trimpSex: trimpSex,
            distanceUnit: distanceUnit
        )
    }

    private func parseOptionalHeartRate(
        _ text: String,
        invalidError: RunnerProfileDraftError
    ) throws -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed) else { throw invalidError }
        return value
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RunnerProfile.key) private var profiles: [RunnerProfile]

    @State private var draft = RunnerProfileDraft()
    @State private var hasLoadedProfile = false
    @State private var isSaving = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    private var profile: RunnerProfile? {
        profiles.first { $0.key == RunnerProfile.singletonKey }
    }

    private var validationMessage: String? {
        do {
            _ = try draft.validatedValues()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var body: some View {
        ZStack {
            Color.flashBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    settingsCard(title: "Heart rate") {
                        heartRateField("Maximum", text: $draft.maxHRText, placeholder: "Auto")
                        Divider().overlay(Color.white.opacity(0.12))
                        heartRateField("Resting", text: $draft.restingHRText, placeholder: "60")
                    }

                    settingsCard(title: "Birthdate") {
                        Toggle("Use birthdate for max HR", isOn: $draft.includesBirthdate)
                            .tint(.blue)

                        if draft.includesBirthdate {
                            DatePicker(
                                "Birthdate",
                                selection: $draft.birthdate,
                                in: ...Date(),
                                displayedComponents: .date
                            )
                            .datePickerStyle(.compact)
                        }
                    }

                    settingsCard(title: "Training load") {
                        Text("Used later to calculate personalized training load.")
                            .font(Font.custom("CallingCode-Regular", size: 13))
                            .foregroundStyle(.white.opacity(0.6))

                        Picker("TRIMP sex", selection: $draft.trimpSex) {
                            ForEach(TRIMPSex.allCases) { value in
                                Text(value.title).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    settingsCard(title: "Distance") {
                        Picker("Preferred unit", selection: $draft.distanceUnit) {
                            ForEach(PreferredDistanceUnit.allCases) { unit in
                                Text(unit.title).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if let validationMessage {
                        Text(validationMessage)
                            .font(Font.custom("CallingCode-Regular", size: 14))
                            .foregroundStyle(.red)
                    } else if let statusMessage {
                        Text(statusMessage)
                            .font(Font.custom("CallingCode-Regular", size: 14))
                            .foregroundStyle(statusIsError ? Color.red : Color.green)
                    }

                    Button(action: save) {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Save")
                            }
                            Spacer()
                        }
                        .font(Font.custom("CallingCode-Regular", size: 20))
                        .padding()
                        .background(Color.gray.opacity(0.25))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(profile == nil || validationMessage != nil || isSaving)
                    .opacity(profile == nil || validationMessage != nil || isSaving ? 0.5 : 1)
                }
                .padding()
            }
        }
        .foregroundStyle(.white)
        .navigationTitle("Settings")
        .toolbarBackground(Color.flashBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            ensureProfileExists()
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(Font.custom("CallingCode-Regular", size: 18))
                .foregroundStyle(.white.opacity(0.7))

            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .font(Font.custom("CallingCode-Regular", size: 16))
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.18))
            .cornerRadius(8)
        }
    }

    private func heartRateField(
        _ title: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
            Text("bpm")
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    @MainActor
    private func ensureProfileExists() {
        guard !hasLoadedProfile else { return }

        if let profile {
            draft = RunnerProfileDraft(profile: profile)
            hasLoadedProfile = true
            return
        }

        let newProfile = RunnerProfile()
        modelContext.insert(newProfile)

        do {
            try modelContext.save()
            draft = RunnerProfileDraft(profile: newProfile)
            hasLoadedProfile = true
        } catch {
            modelContext.delete(newProfile)
            statusMessage = "Could not create settings: \(error.localizedDescription)"
            statusIsError = true
        }
    }

    @MainActor
    private func save() {
        guard let profile else { return }

        do {
            let values = try draft.validatedValues()
            let previousValues = profile.values
            isSaving = true
            profile.apply(values)

            do {
                try modelContext.save()
                statusMessage = "Settings saved."
                statusIsError = false
            } catch {
                profile.apply(previousValues)
                statusMessage = "Could not save settings: \(error.localizedDescription)"
                statusIsError = true
            }
            isSaving = false
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }
}
