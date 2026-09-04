import SwiftData
import SwiftUI

struct PinTitleView: View {
  @Bindable var item: HistoryItem

  var body: some View {
    TextField("", text: $item.title)
      .accessibilityLabel(Text("Alias", tableName: "PinsSettings"))
  }
}

struct PinValueView: View {
  @Bindable var item: HistoryItem
  @State private var editableValue: String
  @State private var isTextContent: Bool
  @State private var isRichText: Bool
  @FocusState private var isEditing: Bool
  @State private var showWarningPopover: Bool = false

  init(item: HistoryItem) {
    self.item = item

    // Inspect type identifiers first so opening this pane doesn't decode large images.
    let contentTypes = Set(item.contents.map(\.type))
    let hasPlainText = contentTypes.contains(NSPasteboard.PasteboardType.string.rawValue)
    let hasImage = StorageType.images.types.contains { contentTypes.contains($0.rawValue) }
    let hasFileURLs = contentTypes.contains(NSPasteboard.PasteboardType.fileURL.rawValue)
    let hasRichText = [NSPasteboard.PasteboardType.rtf, .html].contains {
      contentTypes.contains($0.rawValue)
    }
    self._editableValue = State(
      initialValue: (hasPlainText || hasRichText) && !hasImage && !hasFileURLs
        ? item.previewableText
        : item.title
    )

    // Consider it text content only if it has plain text and doesn't have images or file URLs
    self._isTextContent = State(initialValue: hasPlainText && !hasImage && !hasFileURLs)
    self._isRichText = State(initialValue: hasRichText && !hasImage && !hasFileURLs)
  }

  var body: some View {
    Group {
      if isTextContent || isRichText {
        ZStack(alignment: .trailing) {
          TextField("", text: $editableValue)
            .focused($isEditing)
            .onSubmit {
              updateItemContent()
            }
            .onChange(of: editableValue) { _, _ in
              updateItemContent()
            }
            .padding(.trailing, isRichText ? 40 : 0) // increased space for icon
            .accessibilityLabel(Text("Content", tableName: "PinsSettings"))

          if isRichText && isEditing {
            HStack(spacing: 0) {
              Spacer(minLength: 0)
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .help(Text("RichTextEditWarning", tableName: "PinsSettings"))
              Spacer().frame(width: 4)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(.trailing, 4)
          }
        }
      } else {
        // Non-editable display for non-text content
        Text("ContentIsNotText", tableName: "PinsSettings")
          .foregroundStyle(.secondary)
          .italic()
      }
    }
  }

  private func updateItemContent() {
    // Only update if we're dealing with text or rich text content
    guard isTextContent || isRichText else { return }

    // Remove all non-plain-text content
    let stringType = NSPasteboard.PasteboardType.string.rawValue
    item.contents.removeAll { $0.type != stringType }

    // Update or add the plain text content
    if let index = item.contents.firstIndex(where: { $0.type == stringType }) {
      if let data = editableValue.data(using: .utf8) {
        item.contents[index].value = data
      }
    } else {
      if let data = editableValue.data(using: .utf8) {
        let newContent = HistoryItemContent(type: stringType, value: data)
        item.contents.append(newContent)
      }
    }
    // We don't automatically update title here since we want to preserve
    // OCR-extracted titles for images and other non-text content
  }
}

struct PinsSettingsPane: View {
  @Environment(AppState.self) private var appState
  @Environment(\.modelContext) private var modelContext

  @Query(filter: #Predicate<HistoryItem> { $0.pin != nil }, sort: \.firstCopiedAt)
  private var items: [HistoryItem]

  @State private var selection: Set<PersistentIdentifier> = []
  @State private var searchQuery = ""
  @State private var showDeleteConfirmation = false

  private var filteredItems: [HistoryItem] {
    guard !searchQuery.isEmpty else { return items }
    return items.filter {
      $0.title.localizedStandardContains(searchQuery)
        || ($0.text?.localizedStandardContains(searchQuery) ?? false)
    }
  }

  private var selectedDecorators: [HistoryItemDecorator] {
    appState.history.items.filter { selection.contains($0.item.id) }
  }

  var body: some View {
    VStack(alignment: .leading) {
      HStack {
        TextField(NSLocalizedString("SearchPins", tableName: "PinsSettings", comment: ""), text: $searchQuery)
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 260)

        Text("\(filteredItems.count) / \(items.count)")
          .foregroundStyle(.secondary)

        Spacer()

        Button {
          selection = Set(filteredItems.map(\.id))
        } label: {
          Text("SelectAll", tableName: "PinsSettings")
        }
        .disabled(filteredItems.isEmpty)

        Button {
          selectedDecorators.forEach(appState.history.togglePin)
          selection.removeAll()
        } label: {
          Text("UnpinSelected", tableName: "PinsSettings")
        }
        .disabled(selection.isEmpty)

        Button(role: .destructive) {
          showDeleteConfirmation = true
        } label: {
          Text("DeleteSelected", tableName: "PinsSettings")
        }
        .disabled(selection.isEmpty)
      }

      Table(filteredItems, selection: $selection) {
        TableColumn(Text("Alias", tableName: "PinsSettings")) { item in
          PinTitleView(item: item)
        }

        TableColumn(Text("Content", tableName: "PinsSettings")) { item in
          PinValueView(item: item)
        }
      }
      .onDeleteCommand {
        selectedDecorators.forEach(appState.history.delete)
        selection.removeAll()
      }
      .onChange(of: searchQuery) { selection.removeAll() }

      .confirmationDialog(
        Text("DeleteConfirmationTitle", tableName: "PinsSettings"),
        isPresented: $showDeleteConfirmation
      ) {
        Button(role: .destructive) {
          selectedDecorators.forEach(appState.history.delete)
          selection.removeAll()
        } label: {
          Text("DeleteSelected", tableName: "PinsSettings")
        }
      }

      Text("PinCustomizationDescription", tableName: "PinsSettings")
        .foregroundStyle(.gray)
        .controlSize(.small)
    }
    .frame(minWidth: 500, minHeight: 400)
    .padding()
  }
}

#Preview {
  return PinsSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
    .modelContainer(Storage.shared.container)
}
