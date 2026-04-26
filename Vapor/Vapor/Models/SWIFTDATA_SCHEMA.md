# SwiftData Schema Versioning

## Current State

Vapor uses SwiftData with 8 `@Model` types, defined in `VaporSchema.swift` as `VaporSchemaV1`.

## Models

| Model | File | Relationships |
|---|---|---|
| `PromptRecord` | `PromptRecord.swift` | Standalone |
| `ContextItem` | `ContextItem.swift` | → `ContextItemURLLink`, `ContextItemEntityLink`, `ContextItemImageLink` |
| `ImageAsset` | `ImageAsset.swift` | → `ContextItemImageLink` |
| `ContextItemImageLink` | `ImageAsset.swift` | ← `ContextItem`, ← `ImageAsset` |
| `URLRecord` | `URLRecord.swift` | → `ContextItemURLLink` |
| `ContextItemURLLink` | `URLRecord.swift` | ← `ContextItem`, ← `URLRecord` |
| `EntityRecord` | `EntityRecord.swift` | → `ContextItemEntityLink` |
| `ContextItemEntityLink` | `EntityRecord.swift` | ← `ContextItem`, ← `EntityRecord` |

## Relationship Graph

```
ContextItem ──(1:N cascade)──> ContextItemURLLink ──(N:1)──> URLRecord
ContextItem ──(1:N cascade)──> ContextItemEntityLink ──(N:1)──> EntityRecord
ContextItem ──(1:N cascade)──> ContextItemImageLink ──(N:1)──> ImageAsset
PromptRecord (standalone)
```

## Database Location

`~/Library/Application Support/lol.mrl.app.Vapor/Vapor.store`

Set via `VaporApp.storeURL` — not left to SwiftData's default behavior which is inconsistent across macOS versions.

## How ModelContainer is Created

`VaporApp.swift` calls `ModelContainer.forVapor(url:)` defined in `VaporSchema.swift`. This centralizes the schema so it's defined in one place.

On failure, there's a three-tier fallback:
1. Try opening the persistent store
2. Delete store files and retry
3. Fall back to in-memory store
4. `fatalError` (last resort — should never happen)

## Adding a Schema Migration

When you add, remove, or change a property on any `@Model`, follow these steps:

### 1. Create a new schema version

```swift
// In VaporSchema.swift
enum VaporSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            PromptRecord.self,
            ContextItem.self,
            // ... all models with their new properties
        ]
    }
}
```

### 2. Register the migration stage

```swift
enum VaporMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [VaporSchemaV1.self, VaporSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [MigrateV1toV2.self]
    }
}
```

### 3. Define the migration

For simple additive changes (new optional properties, new models), use `lightweight` migration:

```swift
import SwiftData

enum MigrateV1toV2: SchemaMigrationPlan.MigrationStage {
    static let sourceSchema = VaporSchemaV1.self
    static let destinationSchema = VaporSchemaV2.self

    // If the change is purely additive (new optional columns, new tables),
    // lightweight migration handles it automatically.
    // Set `isLightweight` to `true` (the default).
}
```

For destructive or data-transforming changes (removing columns, renaming, merging):

```swift
enum MigrateV1toV2: SchemaMigrationPlan.MigrationStage {
    static let sourceSchema = VaporSchemaV1.self
    static let destinationSchema = VaporSchemaV2.self

    // Custom migration logic
    static let isLightweight = false

    static func migrate(_ context: SchemaMigrationContext) throws {
        // Access the old store
        let old = context.entities(for: VaporSchemaV1.self)

        // Access the new store
        let new = context.entities(for: VaporSchemaV2.self)

        // Transform data as needed
        // ...
    }
}
```

### 4. Update `VaporSchema.swift`

Update `VaporMigrationPlan.schemas` to include the new version, and add the migration stage to `stages`.

## Current Limitations

The macOS SDK does not yet expose a public `ModelContainer` initializer that accepts a `SchemaMigrationPlan`. Currently `ModelContainer(for: Schema, ...)` is used, which performs automatic lightweight migration for additive changes.

`VaporSchema.swift` defines `VaporSchemaV1`, `VaporMigrationPlan`, and the `ModelContainer.forVapor(url:)` factory so that when the `SchemaMigrationPlan`-accepting API becomes available, only the factory method needs to change — the rest of the migration infrastructure is already in place.

## Enum-to-String Backing Pattern

Several models use raw String properties to store enum values:

| Property | Enum Type |
|---|---|
| `ContextItem.kindRaw` | `ContextItemKind` |
| `ContextItem.statusRaw` | `ProcessingStatus` |
| `ContextItem.extractionBackendRaw` | `EntityExtractionBackend?` |
| `ImageAsset.sourceKindRaw` | `ImageSourceKind` |
| `ImageAsset.lifecycleStateRaw` | `ImageLifecycleState` |
| `ContextItemImageLink.roleRaw` | `ContextImageRole` |
| `ContextItemURLLink.roleRaw` | `ContextURLRole` |
| `EntityRecord.kindRaw` | `EntityKind` |
| `PromptRecord.compressorUsed` | `CompressorType` |

Adding new enum cases is non-destructive — old rows will have the raw string from when they were written, and the computed property should handle unknown values gracefully (e.g. return a default case or `nil`).

## Unique Constraints

| Model | Property | Mechanism |
|---|---|---|
| `ImageAsset` | `contentHash` | `@Attribute(.unique)` |
| `URLRecord` | `urlHash` | `@Attribute(.unique)` |
| `EntityRecord` | `entityHash` | `@Attribute(.unique)` |
