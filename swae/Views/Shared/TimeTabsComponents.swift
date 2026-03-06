//
//  TimeTabsComponents.swift
//  swae
//
//  Created by Kiro on 9/6/25.
//

import SwiftUI

// MARK: - Time Tabs Enum
enum TimeTabs: CaseIterable {
    case upcoming
    case past

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .upcoming:
            "upcoming"
        case .past:
            "past"
        }
    }
}

// MARK: - Custom Segmented Picker
struct CustomSegmentedPicker: View {
    @Binding var selectedTimeTab: TimeTabs
    let onTapAction: () -> Void

    var body: some View {
        HStack {
            ForEach(TimeTabs.allCases, id: \.self) { timeTab in
                CustomSegmentedPickerItem(
                    title: timeTab.localizedStringResource,
                    timeTab: timeTab,
                    selectedTimeTab: $selectedTimeTab,
                    onTapAction: onTapAction
                )
            }
        }
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
    }
}

struct CustomSegmentedPickerItem: View {
    let title: LocalizedStringResource
    let timeTab: TimeTabs
    @Binding var selectedTimeTab: TimeTabs
    let onTapAction: () -> Void

    var body: some View {
        Text(title)
            .font(.subheadline)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(selectedTimeTab == timeTab ? .purple : Color.clear)
            .foregroundColor(selectedTimeTab == timeTab ? .white : .secondary)
            .cornerRadius(8)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedTimeTab = timeTab
                onTapAction()
            }
    }
}
