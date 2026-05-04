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

enum VaporSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

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
            VaporProject.self,
            VaporProjectBookmark.self,
            AISession.self,
            AITurn.self,
            AISessionEntityLink.self,
            AITurnEntityLink.self,
            AISessionTag.self,
            AIGitExportRecord.self,
        ]
    }
}

enum VaporMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [VaporSchemaV1.self, VaporSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
        ]
    }
}

extension ModelContainer {
    static func forVapor(url: URL) throws -> ModelContainer {
        let schema = Schema(VaporSchemaV2.models)
        let config = ModelConfiguration(url: url)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
