import SwiftData
import Foundation

enum VaporSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            PromptRecord.self,
            ContextItem.self,
            URLRecord.self,
            ContextItemURLLink.self,
            EntityRecord.self,
            ContextItemEntityLink.self,
            ImageAsset.self,
            ContextItemImageLink.self,
        ]
    }
}

enum VaporMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [VaporSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        [
        ]
    }
}

extension ModelContainer {
    static func forVapor(url: URL) throws -> ModelContainer {
        let schema = Schema(VaporSchemaV1.models)
        let config = ModelConfiguration(url: url)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
