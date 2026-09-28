//
//  ScreenshotImportView.swift
//  FCTCAttendance
//
//  U6 screenshot capture flow. Picked photos stay in memory. Share-extension files
//  use the protected App Group inbox until this view loads and clears them. Both
//  sources are reduced to the OCR pixel budget before proposal triage.
//

import CoreGraphics
import FCTCAttendanceKit
import PhotosUI
import SwiftUI
import UIKit

struct ScreenshotImportView: View {
    private static let coachPreferenceKey = "screenshotImport.hideCoach"

    let roster: [String]
    let parser: PollScreenshotParser
    let onInitialFilesConsumed: () -> Void
    let onGuestNames: (([String]) -> Void)?
    let onApply: (DraftProposalSet, [String]) -> Void
    let onAddPerson: (String) async throws -> Void
    let onCancel: () -> Void

    @AppStorage(Self.coachPreferenceKey) private var hideCoach = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingCoach: Bool
    @State private var doNotShowAgain = true
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var screenshots: [ImportedScreenshot]
    @State private var initialFileURLs: [URL]
    @State private var didLoadInitialFiles = false
    @State private var isLoadingPhotos = false
    @State private var isRecognizing = false
    @State private var recognizedCount = 0
    @State private var proposalSet: DraftProposalSet?
    @State private var warnings: [ExtractionWarning] = []
    @State private var errorMessage: String?
    @State private var photoLoadTask: Task<Void, Never>?
    @State private var recognitionTask: Task<Void, Never>?
    @State private var photoLoadGeneration = UUID()
    @State private var recognitionGeneration = UUID()
    @State private var coachHasEntered = false

    init(
        roster: [String],
        parser: PollScreenshotParser = PollScreenshotParser(),
        initialImages: [CGImage] = [],
        initialFileURLs: [URL] = [],
        skipCoach: Bool = false,
        onInitialFilesConsumed: @escaping () -> Void = {},
        onGuestNames: (([String]) -> Void)? = nil,
        onApply: @escaping (DraftProposalSet, [String]) -> Void,
        onAddPerson: @escaping (String) async throws -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.roster = roster
        self.parser = parser
        self.onInitialFilesConsumed = onInitialFilesConsumed
        self.onGuestNames = onGuestNames
        self.onApply = onApply
        self.onAddPerson = onAddPerson
        self.onCancel = onCancel
        let preference = UserDefaults.standard.bool(forKey: Self.coachPreferenceKey)
        _showingCoach = State(initialValue: !skipCoach && !preference)
        _screenshots = State(
            initialValue: initialImages.compactMap { image in
                guard let prepared = try? PollScreenshotParser.prepareForRecognition(image) else {
                    return nil
                }
                return ImportedScreenshot(image: prepared)
            }
        )
        _initialFileURLs = State(initialValue: initialFileURLs)
    }

    var body: some View {
        Group {
            if let proposalSet {
                ProposalTriageView(
                    set: proposalSet,
                    roster: roster,
                    onGuestNames: onGuestNames,
                    onApply: { checks in onApply(proposalSet, checks) },
                    onAddPerson: onAddPerson,
                    onCancel: onCancel
                )
            } else if showingCoach {
                coach
            } else {
                picker
            }
        }
        .onDisappear {
            photoLoadTask?.cancel()
            recognitionTask?.cancel()
        }
        .task { await loadInitialFilesIfNeeded() }
    }

    private var coach: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 10) {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 54, weight: .medium))
                            .foregroundStyle(.tint)
                            .symbolEffect(.breathe, options: .repeat(2))
                        Text("Get the names, not just counts")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text("Use the poll's voter list. A screenshot of the chat card does not show who voted.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    // The steps arrive in reading order: the coach is seen
                    // rarely, so a short stagger costs nothing.
                    CoachStep(
                        number: 1,
                        symbol: "hand.tap",
                        title: "Open the poll",
                        detail: "Tap View votes to open the voter list."
                    )
                    .staggeredEntrance(1, hasEntered: coachHasEntered)
                    CoachStep(
                        number: 2,
                        symbol: "camera.viewfinder",
                        title: "Screenshot the list",
                        detail: "Take several screenshots when the names do not fit on one screen."
                    )
                    .staggeredEntrance(2, hasEntered: coachHasEntered)

                    Toggle("Don't show again", isOn: $doNotShowAgain)
                        .padding(.top, 4)

                    Button("Choose screenshots") {
                        if doNotShowAgain { hideCoach = true }
                        showingCoach = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("screenshot-coach-continue")
                }
                .padding(24)
            }
            .navigationTitle("Import a poll")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { coachHasEntered = true }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    private var picker: some View {
        let displayedScreenshots = screenshots
        let screenshotCount = displayedScreenshots.count
        return NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("View votes screenshots", systemImage: "photo.on.rectangle.angled")
                            .font(.headline)
                        Text("Select one or more screenshots. The app reads them on this device and never saves a copy.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: 12,
                        matching: .screenshots
                    ) {
                        Label(
                            screenshotCount == 0 ? "Choose screenshots" : "Change screenshots",
                            systemImage: "photo.badge.plus"
                        )
                    }
                    .disabled(isLoadingPhotos || isRecognizing)
                    .accessibilityIdentifier("screenshot-photo-picker")
                }

                if screenshotCount > 0 {
                    Section("Selected — \(screenshotCount)") {
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 12) {
                                ForEach(displayedScreenshots) { screenshot in
                                    Image(decorative: screenshot.thumbnail, scale: 1)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 78, height: 112)
                                        .clipShape(.rect(cornerRadius: 10))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                                        }
                                        .accessibilityLabel("Selected screenshot")
                                        .transition(.settle(scale: 0.92, reduceMotion: reduceMotion))
                                }
                            }
                            .animation(Motion.snappy, value: displayedScreenshots.map(\.id))
                        }
                        .scrollIndicators(.hidden)

                        Button {
                            recognizeScreenshots()
                        } label: {
                            if isRecognizing {
                                HStack {
                                    ProgressView()
                                    Text("Reading \(recognizedCount) of \(screenshotCount)…")
                                        .contentTransition(.numericText(value: Double(recognizedCount)))
                                        .animation(Motion.snappy, value: recognizedCount)
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                Label("Read screenshots", systemImage: "text.viewfinder")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isLoadingPhotos || isRecognizing)
                        .accessibilityIdentifier("screenshot-read")
                    }
                }

                if isLoadingPhotos {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Preparing screenshots…")
                        }
                    }
                }

                if warnings.contains(.namelessPollCard) {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("The screenshot only contains vote counts", systemImage: "person.crop.circle.badge.questionmark")
                                .font(.headline)
                            Text("Open the poll and tap View votes, screenshot that screen")
                                .foregroundStyle(.secondary)
                            Button("Show instructions") { showingCoach = true }
                        }
                        .padding(.vertical, 4)
                        .accessibilityIdentifier("screenshot-nameless-hint")
                    }
                } else if warnings.contains(.nothingFound) {
                    Section {
                        Label("No voter names were found. Try a clearer screenshot of the View votes screen.", systemImage: "exclamationmark.magnifyingglass")
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Import poll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .onChange(of: pickerItems) { _, items in
                startLoading(items)
            }
        }
    }

    private func startLoading(_ items: [PhotosPickerItem]) {
        photoLoadTask?.cancel()
        recognitionTask?.cancel()
        let generation = UUID()
        photoLoadGeneration = generation
        screenshots = []
        photoLoadTask = Task { await load(items, generation: generation) }
    }

    private func load(_ items: [PhotosPickerItem], generation: UUID) async {
        isLoadingPhotos = true
        errorMessage = nil
        warnings = []
        proposalSet = nil
        defer {
            if photoLoadGeneration == generation {
                isLoadingPhotos = false
                photoLoadTask = nil
            }
        }

        var loaded: [ImportedScreenshot] = []
        for item in items {
            do {
                try Task<Never, Never>.checkCancellation()
                guard let data = try await item.loadTransferable(type: Data.self),
                      !data.isEmpty else {
                    throw ScreenshotImportError.unreadableImage
                }
                // Decode, resize and render the thumbnail away from MainActor. The
                // original bytes stay local to this iteration and are never stored.
                loaded.append(try await ImportedScreenshot.prepare(data: data))
            } catch is CancellationError {
                return
            } catch {
                guard photoLoadGeneration == generation else { return }
                errorMessage = loaded.isEmpty
                    ? "One selected screenshot could not be read."
                    : "Some screenshots could not be read. The others are ready."
            }
        }
        guard !Task.isCancelled, photoLoadGeneration == generation else { return }
        screenshots = loaded
    }

    private func loadInitialFilesIfNeeded() async {
        guard !didLoadInitialFiles, !initialFileURLs.isEmpty else { return }
        didLoadInitialFiles = true
        isLoadingPhotos = true
        errorMessage = nil
        defer {
            initialFileURLs = []
            isLoadingPhotos = false
            onInitialFilesConsumed()
        }

        var loaded: [ImportedScreenshot] = []
        for url in initialFileURLs {
            do {
                try Task<Never, Never>.checkCancellation()
                loaded.append(try await ImportedScreenshot.prepare(fileURL: url))
            } catch is CancellationError {
                return
            } catch {
                errorMessage = loaded.isEmpty
                    ? "One shared screenshot could not be read."
                    : "Some shared screenshots could not be read. The others are ready."
            }
        }
        guard !Task.isCancelled else { return }
        screenshots.append(contentsOf: loaded)
    }

    private func recognizeScreenshots() {
        let images = screenshots.map(\.image)
        guard !images.isEmpty else { return }
        isRecognizing = true
        recognizedCount = 0
        warnings = []
        errorMessage = nil
        recognitionTask?.cancel()
        let generation = UUID()
        recognitionGeneration = generation
        recognitionTask = Task {
            await performRecognition(images: images, generation: generation)
        }
    }

    private func performRecognition(images: [CGImage], generation: UUID) async {
        defer {
            if recognitionGeneration == generation {
                isRecognizing = false
                recognitionTask = nil
            }
        }
        do {
            var lineBatches: [[String]] = []
            lineBatches.reserveCapacity(images.count)
            // Keep Vision requests serial. Each image can consume the full 4 MP
            // budget, and a typical poll needs only a few screenshots.
            for image in images {
                try Task<Never, Never>.checkCancellation()
                lineBatches.append(try await parser.recognizeLines(in: image))
                guard recognitionGeneration == generation else { return }
                recognizedCount += 1
            }
            let extraction = try await parser.extract(screenshots: lineBatches)
            try Task<Never, Never>.checkCancellation()
            guard recognitionGeneration == generation else { return }
            let set = DraftProposalSet(
                entities: extraction.entities,
                matcher: NameMatcher(roster: roster),
                provenance: .ocr
            )
            warnings = extraction.warnings
            if !set.isEmpty {
                proposalSet = set
                screenshots.removeAll()
            }
        } catch is CancellationError {
            return
        } catch {
            guard recognitionGeneration == generation else { return }
            errorMessage = UserFacingError.screenshot(error)
        }
    }
}

private struct CoachStep: View {
    let number: Int
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: symbol)
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.tint)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text("Step \(number)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .textCase(.uppercase)
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 18))
    }
}
