import AppKit
import Foundation
import SQLite3
import SwiftData

@MainActor
class Storage {
  enum CleanupKind {
    case images
    case nonPlainText
  }

  struct CleanupResult {
    let affectedItems: Int
    let deletedItems: Int
    let removedContents: Int
  }

  static let shared = Storage()

  var container: ModelContainer
  var context: ModelContext { container.mainContext }
  var size: String {
    guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).allValues.first?.value as? Int64, size > 1 else {
      return ""
    }

    return ByteCountFormatter().string(fromByteCount: size)
  }

  private let url = URL.applicationSupportDirectory.appending(path: "Maccy/Storage.sqlite")

  init() {
    var config = ModelConfiguration(url: url)

    #if DEBUG
    if AppDelegate.isTesting {
      config = ModelConfiguration(isStoredInMemoryOnly: true)
    }
    #endif

    do {
      container = try ModelContainer(for: HistoryItem.self, configurations: config)
    } catch let error {
      fatalError("Cannot load database: \(error.localizedDescription).")
    }
  }

  func cleanupOrphanedContents() throws -> Int {
    let descriptor = FetchDescriptor<HistoryItemContent>(
      predicate: #Predicate { $0.item == nil }
    )
    let count = try context.fetchCount(descriptor)
    guard count > 0 else {
      return 0
    }

    try context.delete(
      model: HistoryItemContent.self,
      where: #Predicate { $0.item == nil }
    )
    context.processPendingChanges()
    try context.save()

    return count
  }

  // Titles stored before the sanitization in `HistoryItem.generateTitle()` may
  // contain scalars that hang CoreText on macOS 26. Such an item makes Maccy
  // spin at 100% CPU on every launch without ever drawing its window, so the
  // store has to be healed before the history is first rendered.
  // See https://github.com/p0deje/Maccy/issues/1520.
  func sanitizeTitles() throws -> Int {
    let items = try context.fetch(FetchDescriptor<HistoryItem>())
    var count = 0

    for item in items where item.title.containsScalarsUnsafeForTitleLayout {
      item.title = item.title.removingScalarsUnsafeForTitleLayout()
      count += 1
    }

    guard count > 0 else {
      return 0
    }

    context.processPendingChanges()
    try context.save()

    return count
  }

  func cleanupHistory(_ kind: CleanupKind) throws -> CleanupResult {
    let items = try context.fetch(FetchDescriptor<HistoryItem>())
    let plainTextType = NSPasteboard.PasteboardType.string.rawValue
    var affectedItems = 0
    var deletedItems = 0
    var removedContents = 0

    for item in items {
      let contentsToRemove: [HistoryItemContent]
      switch kind {
      case .images:
        contentsToRemove = item.contents.filter { Self.isImageType($0.type) }
        guard !contentsToRemove.isEmpty else { continue }
      case .nonPlainText:
        contentsToRemove = item.contents.filter { $0.type != plainTextType }
        guard !contentsToRemove.isEmpty || item.contents.isEmpty else { continue }
      }

      affectedItems += 1
      let hasPlainText = item.contents.contains { $0.type == plainTextType }
      if !hasPlainText {
        removedContents += item.contents.count
        item.contents.forEach(context.delete)
        item.contents.removeAll()
        context.delete(item)
        deletedItems += 1
      } else {
        removedContents += contentsToRemove.count
        let removedIDs = Set(contentsToRemove.map(\.persistentModelID))
        item.contents.removeAll { removedIDs.contains($0.persistentModelID) }
        contentsToRemove.forEach(context.delete)
      }
    }

    context.processPendingChanges()
    try context.save()
    return CleanupResult(
      affectedItems: affectedItems,
      deletedItems: deletedItems,
      removedContents: removedContents
    )
  }

  private static func isImageType(_ rawType: String) -> Bool {
    if StorageType.images.types.contains(where: { $0.rawValue == rawType }) {
      return true
    }

    let type = rawType.lowercased()
    return type.contains("image")
      || type.contains("jpeg")
      || type.contains("jpg")
      || type.contains("png")
      || type.contains("tiff")
      || type.contains("gif")
      || type.contains("heic")
      || type.contains("bmp")
  }
}

@MainActor
enum HistoryBackup {
  private static let fileManager = FileManager.default
  private static let storageDirectory = URL.applicationSupportDirectory.appending(path: "Maccy")
  private static let storageURL = storageDirectory.appending(path: "Storage.sqlite")
  private static let pendingRestoreURL = storageDirectory.appending(path: "PendingRestore.sqlite")

  static func export() throws -> URL? {
    let panel = NSSavePanel()
    panel.title = NSLocalizedString("ExportBackup", tableName: "StorageSettings", comment: "")
    panel.nameFieldStringValue = "Maccy Backup \(timestamp()).maccybackup"
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let destination = panel.url else { return nil }

    let accessing = destination.startAccessingSecurityScopedResource()
    defer { if accessing { destination.stopAccessingSecurityScopedResource() } }

    let temporary = fileManager.temporaryDirectory
      .appending(path: UUID().uuidString)
      .appendingPathExtension("maccybackup")
    defer { try? fileManager.removeItem(at: temporary) }

    try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
    try createSQLiteSnapshot(at: temporary.appending(path: "Storage.sqlite"))
    let manifest = BackupManifest(formatVersion: 1, createdAt: Date(), appVersion: appVersion())
    let manifestData = try JSONEncoder.maccyBackup.encode(manifest)
    try manifestData.write(to: temporary.appending(path: "manifest.json"), options: .atomic)

    if fileManager.fileExists(atPath: destination.path) {
      try fileManager.removeItem(at: destination)
    }
    try fileManager.copyItem(at: temporary, to: destination)
    return destination
  }

  static func stageImport() throws -> Bool {
    let panel = NSOpenPanel()
    panel.title = NSLocalizedString("ImportBackup", tableName: "StorageSettings", comment: "")
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let source = panel.url else { return false }

    let accessing = source.startAccessingSecurityScopedResource()
    defer { if accessing { source.stopAccessingSecurityScopedResource() } }

    let manifestURL = source.appending(path: "manifest.json")
    let databaseURL = source.appending(path: "Storage.sqlite")
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let manifest = try decoder.decode(BackupManifest.self, from: Data(contentsOf: manifestURL))
    guard manifest.formatVersion == 1 else { throw BackupError.unsupportedFormat }
    guard try databaseIsValid(at: databaseURL) else { throw BackupError.invalidDatabase }

    try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
    let temporaryPending = storageDirectory.appending(path: "PendingRestore-\(UUID().uuidString).sqlite")
    try fileManager.copyItem(at: databaseURL, to: temporaryPending)
    if fileManager.fileExists(atPath: pendingRestoreURL.path) {
      try fileManager.removeItem(at: pendingRestoreURL)
    }
    try fileManager.moveItem(at: temporaryPending, to: pendingRestoreURL)
    return true
  }

  /// Runs before SwiftData opens the store. The previous store is retained in
  /// Application Support so a failed or accidental import remains recoverable.
  static func applyPendingRestoreIfNeeded() throws {
    guard fileManager.fileExists(atPath: pendingRestoreURL.path) else { return }

    let automaticBackup = storageDirectory.appending(path: "Before Restore \(timestamp())")
    try fileManager.createDirectory(at: automaticBackup, withIntermediateDirectories: true)
    let databaseNames = ["Storage.sqlite", "Storage.sqlite-wal", "Storage.sqlite-shm"]

    for name in databaseNames {
      let source = storageDirectory.appending(path: name)
      if fileManager.fileExists(atPath: source.path) {
        try fileManager.copyItem(at: source, to: automaticBackup.appending(path: name))
      }
    }

    do {
      for name in databaseNames {
        let url = storageDirectory.appending(path: name)
        if fileManager.fileExists(atPath: url.path) {
          try fileManager.removeItem(at: url)
        }
      }
      try fileManager.moveItem(at: pendingRestoreURL, to: storageURL)
    } catch {
      for name in databaseNames {
        let backup = automaticBackup.appending(path: name)
        let live = storageDirectory.appending(path: name)
        if fileManager.fileExists(atPath: backup.path), !fileManager.fileExists(atPath: live.path) {
          try? fileManager.copyItem(at: backup, to: live)
        }
      }
      throw error
    }
  }

  private static func createSQLiteSnapshot(at destination: URL) throws {
    try Storage.shared.context.save()

    var sourceDatabase: OpaquePointer?
    var destinationDatabase: OpaquePointer?
    let sourceResult = sqlite3_open_v2(storageURL.path, &sourceDatabase, SQLITE_OPEN_READONLY, nil)
    let destinationFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
    let destinationResult = sqlite3_open_v2(destination.path, &destinationDatabase, destinationFlags, nil)
    guard sourceResult == SQLITE_OK,
          destinationResult == SQLITE_OK,
          let sourceDatabase,
          let destinationDatabase else {
      sqlite3_close(sourceDatabase)
      sqlite3_close(destinationDatabase)
      throw BackupError.cannotOpenDatabase
    }
    defer {
      sqlite3_close(sourceDatabase)
      sqlite3_close(destinationDatabase)
    }

    guard let backup = sqlite3_backup_init(destinationDatabase, "main", sourceDatabase, "main") else {
      throw BackupError.cannotCreateSnapshot
    }
    let result = sqlite3_backup_step(backup, -1)
    let finishResult = sqlite3_backup_finish(backup)
    guard result == SQLITE_DONE, finishResult == SQLITE_OK else {
      throw BackupError.cannotCreateSnapshot
    }
  }

  private static func databaseIsValid(at url: URL) throws -> Bool {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
      sqlite3_close(database)
      throw BackupError.cannotOpenDatabase
    }
    defer { sqlite3_close(database) }

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, "PRAGMA quick_check", -1, &statement, nil) == SQLITE_OK else {
      throw BackupError.invalidDatabase
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW, let result = sqlite3_column_text(statement, 0) else { return false }
    return String(cString: result) == "ok"
  }

  private static func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    return formatter.string(from: Date())
  }

  private static func appVersion() -> String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
  }
}

private struct BackupManifest: Codable {
  let formatVersion: Int
  let createdAt: Date
  let appVersion: String
}

private extension JSONEncoder {
  static var maccyBackup: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }
}

private enum BackupError: LocalizedError {
  case cannotOpenDatabase
  case cannotCreateSnapshot
  case invalidDatabase
  case unsupportedFormat

  var errorDescription: String? {
    switch self {
    case .cannotOpenDatabase:
      return NSLocalizedString("BackupCannotOpenDatabase", tableName: "StorageSettings", comment: "")
    case .cannotCreateSnapshot:
      return NSLocalizedString("BackupCannotCreateSnapshot", tableName: "StorageSettings", comment: "")
    case .invalidDatabase:
      return NSLocalizedString("BackupInvalidDatabase", tableName: "StorageSettings", comment: "")
    case .unsupportedFormat:
      return NSLocalizedString("BackupUnsupportedFormat", tableName: "StorageSettings", comment: "")
    }
  }
}
