import SwiftUI

struct Version {
    let version: String
    let date: String
    let changes: [String]
}

// swiftlint:disable line_length
//private let versions = []

// swiftlint:enable line_length

struct AboutVersionHistorySettingsView: View {
    var body: some View {
        ScrollView {
            HStack {
                LazyVStack(alignment: .leading) {
//                    ForEach(versions, id: \.version) { version in
//                        Text("\(version.version) - \(version.date)")
//                            .font(.title2)
//                            .padding()
//                        VStack(alignment: .leading) {
//                            ForEach(version.changes, id: \.self) { change in
//                                Text(change)
//                            }
//                        }
//                    }
                    Spacer()
                }
                .padding()
                Spacer()
            }
        }
        .navigationTitle("Version history")
    }
}
