//
//  DashboardView.swift
//  FCTCAttendance
//
//  The Dashboard tab (R23–R27): a season at a glance, drawn natively from the
//  offline cache. The view only watches its SwiftData inputs; the kit's
//  `DashboardStore` decides when to rebuild the one model every card reads:
//
//    @Query rows ─> ActiveSeason.fingerprint ─> store.update ─changed─> DashboardModel
//    engine ──────────────────────────────────> store.load ───> picked season, Vs last year
//
//  The header's season menu (the live season and each listed one before it)
//  calls `store.select(season:)`. An earlier season shows from its snapshot.
//
//  Cards, top to bottom, in the approved mockup's order: the headline, Together
//  beside On a roll, The Wall, Vs last year, Every run, the Leaderboard and the
//  Run log. Every pushed screen reads the store's current model, so it updates
//  the moment attendance is recorded, offline included (AE8).
//

import FCTCAttendanceKit
import SwiftData
import SwiftUI

/// The screens the Dashboard pushes. A runner is named, a run is its id.
enum DashboardRoute: Hashable {
    case wall
    case runner(String)
    case runLog
    case run(String)
}

struct DashboardView: View {
    let runtime: AppRuntime
    /// Runs' model, owned by RootTabView: the Dashboard reuses its first-load
    /// and failure states instead of running a second refresh.
    let home: HomeViewModel
    /// The Dashboard tab's stack, owned by RootTabView so an engine swap can reset it.
    @Binding var path: NavigationPath

    @Query(sort: \ScheduledRun.rowIndex) private var cachedRuns: [ScheduledRun]
    @Query(sort: \Member.name) private var cachedMembers: [Member]
    /// Every outbox row, finished ones included (KTD11).
    @Query(sort: \PendingSubmission.createdAt) private var cachedSubmissions: [PendingSubmission]
    @Query private var sheetCaches: [SharedSheetCache]
    @State private var store: DashboardStore
    /// Flips once, so the top cards stagger in on first sight only.
    @State private var hasEntered = false
    @Environment(\.dynamicTypeSize) private var typeSize

    init(runtime: AppRuntime, home: HomeViewModel, path: Binding<NavigationPath>) {
        self.runtime = runtime
        self.home = home
        _path = path
        _store = State(initialValue: DashboardStore(engine: runtime.engine))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 12) {
                    TabHeader(title: "Dashboard", identifier: "dashboard-title") { seasonMenu }
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            // Puts the header where the Runs and Events lists put theirs.
            .contentMargins(.top, Self.headerTop, for: .scrollContent)
            .background(Color(.systemGroupedBackground))
            .onAppear { hasEntered = true }
            // The header row is the title bar (TabHeader), as on Runs.
            .navigationTitle("Dashboard")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: DashboardRoute.self) { destination(for: $0) }
        }
        .onChange(of: fingerprint, initial: true) { _, fingerprint in refresh(fingerprint) }
        // RootTabView pops the stack on a swap; the store follows the new engine.
        .onChange(of: runtime.generation) { _, _ in
            store.replaceEngine(runtime.engine)
            refresh(fingerprint)
        }
    }

    /// The top content margin that lines the header up with the Runs and Events
    /// lists' first row (an inset-grouped List starts its first section lower
    /// than a ScrollView starts its content). `TabNavigationUITests` checks it.
    private static let headerTop: CGFloat = 8

    /// The season menu, beside the title where Runs has its gear. Hidden while
    /// there is only one season to show (a legacy endpoint, the first season).
    @ViewBuilder private var seasonMenu: some View {
        if store.seasons.count > 1, let shown = store.shownSeason {
            Menu {
                Picker("Season", selection: Binding(get: { shown }, set: { year in
                    Task { await store.select(season: year) }
                })) {
                    ForEach(store.seasons, id: \.self) { Text(String($0)).tag($0) }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(String(shown))
                        .font(.headline)
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(height: TabHeader<EmptyView>.rowHeight)
                // A solid capsule in the card color, as Runs draws its gear.
                .background(Color(.secondarySystemGroupedBackground), in: .capsule)
            }
            .accessibilityLabel("Season")
            .accessibilityValue(String(shown))
            .accessibilityIdentifier("dashboard-season")
        }
    }

    @ViewBuilder private var content: some View {
        if let model = store.model {
            if model.runs.isEmpty {
                ContentUnavailableView(
                    "No Runs Yet",
                    systemImage: "chart.bar",
                    description: Text("The Dashboard fills in once the season's first run is recorded.")
                )
                .containerRelativeFrame(.vertical) { height, _ in height * 0.7 }
                .accessibilityIdentifier("dashboard-empty")
            } else {
                cards(model)
            }
        } else if store.showing == .notDownloaded, let season = store.shownSeason {
            SeasonUnavailableView(
                identifier: "dashboard-season-unavailable",
                detail: "The app could not load the \(String(season)) season. Try again when you are back online."
            ) {
                await store.load()
            }
            .containerRelativeFrame(.vertical) { height, _ in height * 0.7 }
        } else if store.showing == .live, home.initialLoadFailed {
            SeasonUnavailableView(
                identifier: "dashboard-unavailable",
                detail: "The app could not load the season. Try again when you are back online."
            ) {
                await home.retry(hasCachedState: false)
            }
            .containerRelativeFrame(.vertical) { height, _ in height * 0.7 }
        } else {
            SeasonLoadingView(identifier: "dashboard-loading")
                .containerRelativeFrame(.vertical) { height, _ in height * 0.7 }
        }
    }

    @ViewBuilder private func cards(_ model: DashboardModel) -> some View {
        HeadlineCard(headline: model.headline, recentRuns: Array(model.recentRuns),
                     unsyncedCount: store.unsyncedCount, accent: accent)
            .staggeredEntrance(0, hasEntered: hasEntered)

        pairLayout {
            TogetherCard(headline: model.headline)
            OnARollCard(onARoll: model.onARoll, accent: accent)
        }
        .fixedSize(horizontal: false, vertical: true)
        .staggeredEntrance(1, hasEntered: hasEntered)

        WallCard(wall: model.recentWall, accent: accent, open: openRunner)
            .staggeredEntrance(2, hasEntered: hasEntered)

        switch store.lastSeason {
        case .loaded:
            if let progress = model.progress {
                VsLastYearCard(progress: progress, accent: accent)
            }
        case .notDownloaded:
            LastSeasonMissingCard()
        case .loading, .unavailable:
            // Legacy endpoints and first seasons have nothing to compare.
            EmptyView()
        }

        EveryRunCard(runs: Array(model.recentRuns.suffix(EveryRunCard.count)), accent: accent)
        LeaderboardCard(leaderboard: model.leaderboard, accent: accent)
        RunLogLink(count: model.runs.count)
    }

    /// Side by side, or stacked at accessibility sizes so neither card squeezes.
    private var pairLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }

    @ViewBuilder private func destination(for route: DashboardRoute) -> some View {
        switch route {
        case .wall:
            WallView(wall: store.model?.wall, accent: accent, open: openRunner)
        case .runner(let name):
            RunnerView(name: name, detail: store.model?.runners[name],
                       seasonRuns: store.model?.runs.count ?? 0, accent: accent)
        case .runLog:
            RunLogView(runs: store.model?.runs ?? [])
        case .run(let id):
            RunDetailView(entry: store.model?.runs.first { $0.id == id })
        }
    }

    /// The user's accent, passed explicitly so chart marks draw it too.
    private var accent: Color { runtime.accent.color }

    /// Chart taps have no NavigationLink, so they push through the path.
    private func openRunner(_ name: String) {
        path.append(DashboardRoute.runner(name))
    }

    private var fingerprint: String {
        ActiveSeason.fingerprint(runtime: runtime, runs: cachedRuns, members: cachedMembers,
                                 submissions: cachedSubmissions, caches: sheetCaches)
    }

    /// Hands the store this change. The inputs closure runs only when the
    /// fingerprint moved, so the cache is read once per data change.
    private func refresh(_ fingerprint: String) {
        store.update(fingerprint: fingerprint) {
            let season = ActiveSeason(runtime: runtime, runs: cachedRuns, members: cachedMembers,
                                      submissions: cachedSubmissions)
            let runs = season.effective.clubRuns
            guard let year = runs.map(\.season).max() ?? season.state?.seasonYear, year > 0 else { return nil }
            return DashboardInputs(season: year, runs: runs, priors: season.priors,
                                   unsyncedCount: season.effective.unsyncedCount,
                                   listedSeasons: season.state?.supportedSeasons?.map(\.seasonYear) ?? [])
        }
        Task { await store.load() }
    }
}
