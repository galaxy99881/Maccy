import AppKit
import Defaults
import Settings
import SwiftUI

struct StorageSettingsPane: View {
  @Observable
  class ViewModel {
    var saveFiles = false {
      didSet {
        Defaults.withoutPropagation {
          if saveFiles {
            Defaults[.enabledPasteboardTypes].formUnion(StorageType.files.types)
          } else {
            Defaults[.enabledPasteboardTypes].subtract(StorageType.files.types)
          }
        }
      }
    }

    var saveImages = false {
      didSet {
        Defaults.withoutPropagation {
          if saveImages {
            Defaults[.enabledPasteboardTypes].formUnion(StorageType.images.types)
          } else {
            Defaults[.enabledPasteboardTypes].subtract(StorageType.images.types)
          }
        }
      }
    }

    var saveText = false {
      didSet {
        Defaults.withoutPropagation {
          if saveText {
            Defaults[.enabledPasteboardTypes].formUnion(StorageType.text.types)
          } else {
            Defaults[.enabledPasteboardTypes].subtract(StorageType.text.types)
          }
        }
      }
    }

    private var observer: Defaults.Observation?

    init() {
      observer = Defaults.observe(.enabledPasteboardTypes) { change in
        self.saveFiles = change.newValue.isSuperset(of: StorageType.files.types)
        self.saveImages = change.newValue.isSuperset(of: StorageType.images.types)
        self.saveText = change.newValue.isSuperset(of: StorageType.text.types)
      }
    }

    deinit {
      observer?.invalidate()
    }
  }

  @Default(.size) private var size
  @Default(.sortBy) private var sortBy
  @Default(.unlimitedPlainTextMode) private var unlimitedPlainTextMode

  @State private var viewModel = ViewModel()
  @State private var storageSize = Storage.shared.size
  @State private var isCleaning = false

  private var unlimitedHistory: Binding<Bool> {
    Binding(
      get: { unlimitedPlainTextMode },
      set: { enabled in
        unlimitedPlainTextMode = enabled
        if enabled {
          size = 0
        } else {
          size = 200
        }
      }
    )
  }

  private let sizeFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 1
    formatter.maximum = 999
    return formatter
  }()

  var body: some View {
    Settings.Container(contentWidth: 450) {
      Settings.Section(
        bottomDivider: true,
        label: { Text("Save", tableName: "StorageSettings") }
      ) {
        Toggle(
          isOn: $viewModel.saveFiles,
          label: { Text("Files", tableName: "StorageSettings") }
        )
        .disabled(unlimitedPlainTextMode)
        Toggle(
          isOn: $viewModel.saveImages,
          label: { Text("Images", tableName: "StorageSettings") }
        )
        .disabled(unlimitedPlainTextMode)
        Toggle(
          isOn: $viewModel.saveText,
          label: { Text("Text", tableName: "StorageSettings") }
        )
        .disabled(unlimitedPlainTextMode)
        Text("SaveDescription", tableName: "StorageSettings")
          .controlSize(.small)
          .foregroundStyle(.gray)
      }

      Settings.Section(label: { Text("Size", tableName: "StorageSettings") }) {
        HStack {
          TextField("", value: $size, formatter: sizeFormatter)
            .frame(width: 80)
            .disabled(unlimitedPlainTextMode)
            .help(Text("SizeTooltip", tableName: "StorageSettings"))
            .accessibilityLabel(Text("Size", tableName: "StorageSettings"))
          Stepper("", value: $size, in: 1...999)
            .labelsHidden()
            .disabled(unlimitedPlainTextMode)
            .accessibilityLabel(Text("Size", tableName: "StorageSettings"))
          Toggle(isOn: unlimitedHistory) {
            Text("Unlimited", tableName: "StorageSettings")
          }
          .toggleStyle(.checkbox)
          .help(Text("UnlimitedTooltip", tableName: "StorageSettings"))
          Text(storageSize)
            .controlSize(.small)
            .foregroundStyle(.gray)
            .help(Text("CurrentSizeTooltip", tableName: "StorageSettings"))
            .onAppear {
              storageSize = Storage.shared.size
            }
        }
      }

      Settings.Section(label: { Text("SortBy", tableName: "StorageSettings") }) {
        Picker("", selection: $sortBy) {
          ForEach(Sorter.By.allCases) { mode in
            Text(mode.description)
          }
        }
        .labelsHidden()
        .frame(width: 160, alignment: .leading)
        .help(Text("SortByTooltip", tableName: "StorageSettings"))
          .accessibilityLabel(Text("SortBy", tableName: "StorageSettings"))
      }

      Settings.Section(label: { Text("Backup", tableName: "StorageSettings") }) {
        HStack {
          Button(action: exportBackup) {
            Text("ExportBackup", tableName: "StorageSettings")
          }
          Button(action: importBackup) {
            Text("ImportBackup", tableName: "StorageSettings")
          }
        }
        Text("BackupDescription", tableName: "StorageSettings")
          .controlSize(.small)
          .foregroundStyle(.gray)
      }

      Settings.Section(label: { Text("Cleanup", tableName: "StorageSettings") }) {
        HStack {
          Button {
            confirmCleanup(.images)
          } label: {
            Text("RemoveImages", tableName: "StorageSettings")
          }
          .disabled(isCleaning)

          Button {
            confirmCleanup(.nonPlainText)
          } label: {
            Text("KeepPlainTextOnly", tableName: "StorageSettings")
          }
          .disabled(isCleaning)
        }
        Text("CleanupDescription", tableName: "StorageSettings")
          .controlSize(.small)
          .foregroundStyle(.gray)
      }
    }
  }

  private func exportBackup() {
    do {
      guard let url = try HistoryBackup.export() else { return }
      showAlert(
        title: NSLocalizedString("BackupExported", tableName: "StorageSettings", comment: ""),
        message: url.path
      )
    } catch {
      NSAlert(error: error).runModal()
    }
  }

  private func importBackup() {
    let confirmation = NSAlert()
    confirmation.messageText = NSLocalizedString("ImportConfirmationTitle", tableName: "StorageSettings", comment: "")
    confirmation.informativeText = NSLocalizedString(
      "ImportConfirmationMessage",
      tableName: "StorageSettings",
      comment: ""
    )
    confirmation.alertStyle = .warning
    confirmation.addButton(withTitle: NSLocalizedString("Continue", tableName: "StorageSettings", comment: ""))
    confirmation.addButton(withTitle: NSLocalizedString("Cancel", tableName: "StorageSettings", comment: ""))
    guard confirmation.runModal() == .alertFirstButtonReturn else { return }

    do {
      guard try HistoryBackup.stageImport() else { return }
      showAlert(
        title: NSLocalizedString("ImportReady", tableName: "StorageSettings", comment: ""),
        message: NSLocalizedString("ImportReadyMessage", tableName: "StorageSettings", comment: "")
      )
      NSApp.terminate(nil)
    } catch {
      NSAlert(error: error).runModal()
    }
  }

  private func confirmCleanup(_ kind: Storage.CleanupKind) {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("CleanupConfirmationTitle", tableName: "StorageSettings", comment: "")
    alert.informativeText = NSLocalizedString("CleanupConfirmationMessage", tableName: "StorageSettings", comment: "")
    alert.alertStyle = .critical
    alert.addButton(withTitle: NSLocalizedString("ExportBackupFirst", tableName: "StorageSettings", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("CleanNow", tableName: "StorageSettings", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("Cancel", tableName: "StorageSettings", comment: ""))

    switch alert.runModal() {
    case .alertFirstButtonReturn:
      exportBackup()
    case .alertSecondButtonReturn:
      performCleanup(kind)
    default:
      break
    }
  }

  private func performCleanup(_ kind: Storage.CleanupKind) {
    isCleaning = true
    do {
      let result = try Storage.shared.cleanupHistory(kind)
      storageSize = Storage.shared.size
      Task { @MainActor in
        try? await AppState.shared.history.load()
      }
      let format = NSLocalizedString("CleanupCompletedMessage", tableName: "StorageSettings", comment: "")
      showAlert(
        title: NSLocalizedString("CleanupCompleted", tableName: "StorageSettings", comment: ""),
        message: String(format: format, result.affectedItems, result.deletedItems, result.removedContents)
      )
    } catch {
      NSAlert(error: error).runModal()
    }
    isCleaning = false
  }

  private func showAlert(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.runModal()
  }
}

#Preview {
  StorageSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
