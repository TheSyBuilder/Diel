import SwiftData

/// Keep V1's model list frozen so existing stores can migrate without losing records.
nonisolated enum DielSchemaV1: VersionedSchema {
  static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
  static var models: [any PersistentModel.Type] {
    [RawGarminResponse.self, GarminDayRecord.self, GarminActivityRecord.self, GarminSyncState.self]
  }
}

nonisolated enum DielSchemaV2: VersionedSchema {
  static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
  static var models: [any PersistentModel.Type] {
    DielSchemaV1.models + [ComputedDayRecord.self]
  }
}

nonisolated enum DielSchemaV3: VersionedSchema {
  static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
  static var models: [any PersistentModel.Type] {
    DielSchemaV2.models + [CheckIn.self]
  }
}

nonisolated enum DielSchemaV4: VersionedSchema {
  static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }
  static var models: [any PersistentModel.Type] { DielSchemaV3.models + [BriefRecord.self] }
}

nonisolated enum DielSchemaV5: VersionedSchema {
  static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }
  static var models: [any PersistentModel.Type] { DielSchemaV4.models + [ReminderPreferences.self] }
}

nonisolated enum DielMigrationPlan: SchemaMigrationPlan {
  static var schemas: [any VersionedSchema.Type] {
    [DielSchemaV1.self, DielSchemaV2.self, DielSchemaV3.self, DielSchemaV4.self, DielSchemaV5.self]
  }
  static var stages: [MigrationStage] {
    [
      .lightweight(fromVersion: DielSchemaV1.self, toVersion: DielSchemaV2.self),
      .lightweight(fromVersion: DielSchemaV2.self, toVersion: DielSchemaV3.self),
      .lightweight(fromVersion: DielSchemaV3.self, toVersion: DielSchemaV4.self),
      .lightweight(fromVersion: DielSchemaV4.self, toVersion: DielSchemaV5.self),
    ]
  }
}
