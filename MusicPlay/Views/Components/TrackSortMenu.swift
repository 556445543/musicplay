import SwiftUI

struct TrackSortMenuContent: View {
    @Binding var sort: TrackSort

    var body: some View {
        ForEach(TrackSortOption.allCases) { option in
            Button {
                guard sort.option != option else { return }
                sort = TrackSort(option: option, ascending: option.preferredAscending)
            } label: {
                if sort.option == option {
                    Label(option.label, systemImage: "checkmark")
                } else {
                    Text(option.label)
                }
            }
        }

        Divider()

        Button {
            sort = TrackSort(option: sort.option, ascending: true)
        } label: {
            if sort.ascending {
                Label("升序", systemImage: "checkmark")
            } else {
                Text("升序")
            }
        }

        Button {
            sort = TrackSort(option: sort.option, ascending: false)
        } label: {
            if sort.ascending {
                Text("降序")
            } else {
                Label("降序", systemImage: "checkmark")
            }
        }
    }
}
