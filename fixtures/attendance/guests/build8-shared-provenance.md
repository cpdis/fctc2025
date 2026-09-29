# Build 8 migration fixture

`build8-shared.store` is a 152 KB SwiftData store created on 29 September 2026 by the app
at `main` e2d479d, the code TestFlight build 8 ships. It was captured from a simulator launch
with `-ui-testing -ui-shared-guests -ui-store-name <uuid>`, so it holds only the synthetic
shared UI-test fake: 4 members, 9 cached runs and one `SharedSheetCache` row
(`https://ui-test.invalid/exec:ui-book:26`, season 26).

It predates `SharedSheetCache.liveAt`. The WAL was checkpointed (`PRAGMA wal_checkpoint(TRUNCATE)`)
before the copy, so no sidecar is needed. `GuestMigrationTests` copies it to a temporary
directory, opens it with the current schema, and checks the row survives with `liveAt` nil.
Do not regenerate this fixture with the new models: it proves the build 8 upgrade.
