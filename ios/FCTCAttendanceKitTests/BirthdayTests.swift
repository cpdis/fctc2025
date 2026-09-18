import Foundation
import SwiftData
import Testing

@testable import FCTCAttendanceKit

@Suite("Birthday board")
struct BirthdayBoardTests {
    @Test("Today and day thirty are included, yesterday and day thirty-one are not")
    func inclusiveWindow() {
        let birthdays = [
            MemberBirthday(name: "Today", month: 9, day: 18),
            MemberBirthday(name: "Last day", month: 10, day: 18),
            MemberBirthday(name: "Too far", month: 10, day: 19),
            MemberBirthday(name: "Yesterday", month: 9, day: 17),
        ]
        let result = BirthdayBoard.upcoming(from: birthdays, now: instant("2026-09-18T10:00:00Z"))
        #expect(result.map(\.name) == ["Today", "Last day"])
        #expect(result.map(\.daysUntil) == [0, 30])
    }

    @Test("December birthdays wrap into January and ties use names")
    func newYearAndTies() {
        let result = BirthdayBoard.upcoming(from: [
            .init(name: "Zoe", month: 1, day: 1),
            .init(name: "Adam", month: 1, day: 1),
            .init(name: "claire", month: 1, day: 1),
            .init(name: "Émile", month: 1, day: 1),
            .init(name: "December", month: 12, day: 31),
        ], now: instant("2026-12-30T04:00:00Z"))
        #expect(result.map(\.name) == ["December", "Adam", "claire", "Émile", "Zoe"])
        #expect(result.map(\.daysUntil) == [1, 2, 2, 2, 2])
    }

    @Test("The club's date changes at midnight in Perth, regardless of device zone")
    func perthBoundary() {
        let birthdays = [MemberBirthday(name: "September", month: 9, day: 19)]
        #expect(BirthdayBoard.upcoming(from: birthdays, now: instant("2026-09-18T15:59:59Z")).first?.daysUntil == 1)
        #expect(BirthdayBoard.upcoming(from: birthdays, now: instant("2026-09-18T16:00:00Z")).first?.daysUntil == 0)
        #expect(BirthdayBoard.upcoming(from: birthdays, now: instant("2026-09-19T16:00:00Z")).isEmpty)
    }

    @Test("February 29 is observed on February 28 outside a leap year")
    func leapDay() {
        let birthdays = [MemberBirthday(name: "Leap", month: 2, day: 29)]
        let ordinary = BirthdayBoard.upcoming(from: birthdays, now: instant("2027-02-28T04:00:00Z"))
        let leap = BirthdayBoard.upcoming(from: birthdays, now: instant("2028-02-28T04:00:00Z"))
        #expect(ordinary.first?.daysUntil == 0)
        #expect(ordinary.first?.day == 29, "The recorded birthday is retained")
        #expect(leap.first?.daysUntil == 1)
        #expect(BirthdayBoard.upcoming(from: birthdays, now: instant("2027-03-01T04:00:00Z")).isEmpty)
    }

    @Test("Invalid dates never roll into another month")
    func malformedDates() {
        let invalid = [(0, 1), (13, 1), (4, 31), (2, 30), (1, 0), (1, -1), (1, 32)]
            .map { MemberBirthday(name: "Invalid", month: $0.0, day: $0.1) }
        #expect(invalid.allSatisfy { !$0.isValid })
        #expect(!MemberBirthday(name: " ", month: 9, day: 18).isValid)
        #expect(BirthdayBoard.upcoming(from: invalid, now: instant("2026-09-18T04:00:00Z")).isEmpty)
    }

    private func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
}

@Suite("Birthday state and cache")
struct BirthdayCacheTests {
    @Test("The wire contract distinguishes an older server from an empty birthday row")
    func wireCompatibility() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(SheetState.self, from: Data("{}".utf8)).birthdays == nil)
        #expect(try decoder.decode(SheetState.self, from: Data(#"{"birthdays":[]}"#.utf8)).birthdays == [])
        let state = SheetState(birthdays: [.init(name: "Aaron", month: 9, day: 1)])
        #expect(try decoder.decode(SheetState.self, from: JSONEncoder().encode(state)) == state)
    }

    @Test("Both endpoint formats cache birthdays; missing data preserves and an empty list clears", arguments: [false, true])
    func cacheRefresh(shared: Bool) async throws {
        let container = try makeContainer()
        let birthday = MemberBirthday(name: "Aaron", month: 9, day: 1)
        var state = SheetState(roster: [.init(name: "Aaron", colIndex: 6)], birthdays: [birthday])
        if shared {
            state.capabilities = GuestCapabilities()
            state.spreadsheetId = "book"
            state.seasonSheetId = 2026
        }
        let transport = StubTransport([.response(try response(state))])
        let engine = SyncEngine(modelContainer: container, api: SheetAPI(config: configuredAPI, transport: transport), automaticallyDrains: false)
        _ = try await engine.refreshState()
        #expect(try cachedBirthday(container) == birthday)
        if shared {
            #expect(try ModelContext(container).fetch(FetchDescriptor<SharedSheetCache>()).first?.state?.birthdays == [birthday])
        }

        state.birthdays = nil
        await transport.append(.response(try response(state)))
        _ = try await engine.refreshState()
        #expect(try cachedBirthday(container) == birthday)
        if shared {
            #expect(try ModelContext(container).fetch(FetchDescriptor<SharedSheetCache>()).first?.state?.birthdays == [birthday])
        }

        state.birthdays = []
        await transport.append(.response(try response(state)))
        _ = try await engine.refreshState()
        #expect(try cachedBirthday(container) == nil)
        if shared {
            #expect(try ModelContext(container).fetch(FetchDescriptor<SharedSheetCache>()).first?.state?.birthdays == [])
        }
    }

    @Test("A different endpoint cannot use the previous endpoint's birthdays")
    func endpointIsolation() async throws {
        let container = try makeContainer()
        let state = SheetState(roster: [.init(name: "Aaron", colIndex: 6)], birthdays: [.init(name: "Aaron", month: 9, day: 1)])
        let first = SyncEngine(modelContainer: container, api: SheetAPI(config: configuredAPI,
            transport: StubTransport([.response(try response(state))])), automaticallyDrains: false)
        _ = try await first.refreshState()
        let other = AppConfig(endpoint: URL(string: "https://script.google.com/macros/s/OTHER/exec")!, secret: "test")
        #expect(try ModelContext(container).fetch(FetchDescriptor<Member>()).first?.birthday(for: other.endpoint?.absoluteString) == nil)
        let second = SyncEngine(modelContainer: container, api: SheetAPI(config: other,
            transport: StubTransport([.response(try response(SheetState(roster: state.roster)))])), automaticallyDrains: false)
        _ = try await second.refreshState()
        #expect(try cachedBirthday(container) == nil)
        let switched = try #require(ModelContext(container).fetch(FetchDescriptor<Member>()).first)
        #expect(switched.birthdayEndpointIdentity == nil)
        #expect(switched.birthdaySeasonYear == nil)
    }

    @Test("A missing birthday field remains unknown until an empty list is confirmed")
    func unknownVersusEmpty() async throws {
        let container = try makeContainer()
        var state = SheetState(roster: [.init(name: "Aaron", colIndex: 6)], seasonYear: 2026)
        let transport = StubTransport([.response(try response(state))])
        let engine = SyncEngine(modelContainer: container, api: SheetAPI(config: configuredAPI,
            transport: transport), automaticallyDrains: false)
        _ = try await engine.refreshState()
        let unknown = try #require(ModelContext(container).fetch(FetchDescriptor<Member>()).first)
        #expect(unknown.birthdayEndpointIdentity == nil)
        #expect(unknown.birthdaySeasonYear == nil)

        state.birthdays = []
        await transport.append(.response(try response(state)))
        _ = try await engine.refreshState()
        let empty = try #require(ModelContext(container).fetch(FetchDescriptor<Member>()).first)
        #expect(empty.birthdayEndpointIdentity == configuredAPI.endpoint?.absoluteString)
        #expect(empty.birthdaySeasonYear == 2026)
        #expect(empty.birthdayMonth == nil)
        #expect(empty.birthdayDay == nil)
    }

    @Test("Historical season dates cannot appear in the current season's cache fallback")
    func seasonIsolation() async throws {
        let container = try makeContainer()
        let birthday = MemberBirthday(name: "Aaron", month: 9, day: 1)
        let state = SheetState(roster: [.init(name: "Aaron", colIndex: 6)], seasonYear: 2025, birthdays: [birthday])
        let engine = SyncEngine(modelContainer: container, api: SheetAPI(config: configuredAPI,
            transport: StubTransport([.response(try response(state))])), automaticallyDrains: false)
        _ = try await engine.refreshState()
        let member = try #require(ModelContext(container).fetch(FetchDescriptor<Member>()).first)
        #expect(member.birthday(for: configuredAPI.endpoint?.absoluteString, seasonYear: 2025) == birthday)
        #expect(member.birthday(for: configuredAPI.endpoint?.absoluteString, seasonYear: 2026) == nil)
    }

    @Test("Malformed dates clear stale values, and removed roster members lose their birthdays")
    func invalidAndRemoved() async throws {
        let container = try makeContainer()
        let roster = [RosterEntry(name: "Aaron", colIndex: 6)]
        let states = [
            SheetState(roster: roster, birthdays: [.init(name: "Aaron", month: 9, day: 1)]),
            SheetState(roster: roster, birthdays: [.init(name: "Aaron", month: 4, day: 31)]),
            SheetState(roster: [], birthdays: [.init(name: "Aaron", month: 9, day: 1)]),
        ]
        let engine = SyncEngine(modelContainer: container, api: SheetAPI(config: configuredAPI,
            transport: StubTransport(try states.map { .response(try response($0)) })), automaticallyDrains: false)
        _ = try await engine.refreshState()
        _ = try await engine.refreshState()
        #expect(try cachedBirthday(container) == nil)
        _ = try await engine.refreshState()
        #expect(try ModelContext(container).fetch(FetchDescriptor<Member>()).isEmpty)
    }

    @Test("A store reopened without a network refresh retains the scoped birthday")
    func offlineRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("birthday-cache-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("cache.store")
        try await populateStore(at: url)
        let reopened = try ModelContainer(for: AttendanceSchema.schema,
            configurations: ModelConfiguration(schema: AttendanceSchema.schema, url: url))
        #expect(try cachedBirthday(reopened) == MemberBirthday(name: "Aaron", month: 9, day: 1))
    }

    @Test("Current birthdays survive historical refresh, an older response, and offline relaunch", arguments: [false, true])
    func sharedSeasonOfflineRelaunch(clearAfterward: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("birthday-seasons-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("cache.store")
        try await populateSeasonSnapshots(at: url, clearAfterward: clearAfterward)
        let reopened = try ModelContainer(for: AttendanceSchema.schema,
            configurations: ModelConfiguration(schema: AttendanceSchema.schema, url: url))
        let snapshots = try ModelContext(reopened).fetch(FetchDescriptor<SharedSheetCache>())
        let current = try #require(snapshots.first { $0.seasonSheetId == 2026 })
        let historical = try #require(snapshots.first { $0.seasonSheetId == 2025 })
        let expected: [MemberBirthday] = clearAfterward ? [] : [.init(name: "Aaron", month: 9, day: 1)]
        #expect(current.state?.birthdays == expected)
        #expect(historical.state?.birthdays == [])
    }

    @Test("An older response preserves birthdays only for the refreshed roster")
    func removedMemberDoesNotKeepBirthday() async throws {
        let container = try makeContainer()
        let kept = MemberBirthday(name: "Col", month: 9, day: 18)
        let current = SheetState(roster: [.init(name: "Aaron", colIndex: 6), .init(name: "Col", colIndex: 7)],
            seasonYear: 2026, birthdays: [.init(name: "Aaron", month: 10, day: 1), kept],
            capabilities: GuestCapabilities(), spreadsheetId: "book", seasonSheetId: 2026)
        var olderResponse = current
        olderResponse.roster = [.init(name: "Col", colIndex: 6)]
        olderResponse.birthdays = nil
        let engine = SyncEngine(modelContainer: container, api: SheetAPI(config: configuredAPI,
            transport: StubTransport(try [current, olderResponse].map { .response(try response($0)) })), automaticallyDrains: false)
        _ = try await engine.refreshState()
        _ = try await engine.refreshState()
        let cache = try #require(ModelContext(container).fetch(FetchDescriptor<SharedSheetCache>()).first)
        #expect(cache.state?.birthdays == [kept])
    }

    private func populateSeasonSnapshots(at url: URL, clearAfterward: Bool) async throws {
        let container = try ModelContainer(for: AttendanceSchema.schema,
            configurations: ModelConfiguration(schema: AttendanceSchema.schema, url: url))
        let current = SheetState(roster: [.init(name: "Aaron", colIndex: 6)], seasonYear: 2026,
            birthdays: [.init(name: "Aaron", month: 9, day: 1)], capabilities: GuestCapabilities(),
            spreadsheetId: "book", seasonSheetId: 2026)
        var historical = current
        historical.seasonYear = 2025
        historical.seasonSheetId = 2025
        historical.birthdays = []
        var olderResponse = current
        olderResponse.birthdays = nil
        var states = [current, historical, olderResponse]
        if clearAfterward {
            var cleared = current
            cleared.birthdays = []
            states.append(cleared)
        }
        let engine = SyncEngine(modelContainer: container, api: SheetAPI(config: configuredAPI,
            transport: StubTransport(try states.map { .response(try response($0)) })), automaticallyDrains: false)
        for state in states { _ = try await engine.refreshState(seasonSheetId: state.seasonSheetId) }
    }

    private func populateStore(at url: URL) async throws {
        let container = try ModelContainer(for: AttendanceSchema.schema,
            configurations: ModelConfiguration(schema: AttendanceSchema.schema, url: url))
        let state = SheetState(roster: [.init(name: "Aaron", colIndex: 6)], birthdays: [.init(name: "Aaron", month: 9, day: 1)])
        let engine = SyncEngine(modelContainer: container, api: SheetAPI(config: configuredAPI,
            transport: StubTransport([.response(try response(state))])), automaticallyDrains: false)
        _ = try await engine.refreshState()
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: AttendanceSchema.schema,
            configurations: ModelConfiguration(schema: AttendanceSchema.schema, isStoredInMemoryOnly: true))
    }

    private func cachedBirthday(_ container: ModelContainer) throws -> MemberBirthday? {
        try ModelContext(container).fetch(FetchDescriptor<Member>()).first?.birthday(for: configuredAPI.endpoint?.absoluteString)
    }

    private func response(_ state: SheetState) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        object["ok"] = true
        return try JSONSerialization.data(withJSONObject: object)
    }
}
