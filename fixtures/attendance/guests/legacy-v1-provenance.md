# Installed-schema migration fixture

`legacy-v1.store` is a copy of an 88 KB SwiftData store created on 16 September 2026.
The capture used the app models before the shared-guest schema change.
It contains only synthetic `Col` and `Rene` examples.

The store contains one cached run and two local submissions:

- `aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa`: queued, row 42, `Rene`.
- `bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb`: legacy `done`, row 41, `Rene`.

The captured WAL was empty. The fixture is checkpointed SQLite; no sidecar is needed.
`GuestMigrationTests` copies it to a temporary directory before opening it.
The test checks names, queue state, ambiguous legacy evidence, and absence of automatic network writes.
Do not regenerate this fixture with the new models: it proves an installed-schema upgrade.
