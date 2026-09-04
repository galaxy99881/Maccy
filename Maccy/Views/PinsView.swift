import SwiftUI

struct PinsView: View {
  private static let visibleRowLimit = 8

  @Environment(AppState.self) private var appState

  var items: [HistoryItemDecorator]

  var body: some View {
    VStack(spacing: 0) {
      if items.count > Self.visibleRowLimit {
        HStack(spacing: 6) {
          Image(systemName: "pin.fill")
          Text(items.count, format: .number)
          Spacer()
          Button {
            appState.popup.close()
            appState.openPinsPreferences()
          } label: {
            Image(systemName: "slider.horizontal.3")
          }
          .buttonStyle(.borderless)
          .help(Text("Title", tableName: "PinsSettings"))
          .accessibilityLabel(Text("Title", tableName: "PinsSettings"))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: Popup.itemHeight)
      }

      if items.count > Self.visibleRowLimit {
        ScrollView {
          ScrollViewReader { proxy in
            list
              .task(id: appState.navigator.scrollTarget) {
                guard let target = appState.navigator.scrollTarget,
                      items.contains(where: { $0.id == target }) else { return }
                proxy.scrollTo(target)
              }
          }
        }
        .frame(height: CGFloat(Self.visibleRowLimit) * Popup.itemHeight)
      } else {
        list
      }
    }
  }

  private var list: some View {
          MultipleSelectionListView(items: items) { previous, item, next, index in
            HistoryItemView(item: item, previous: previous, next: next, index: index)
          }
  }
}
