import Foundation

enum HistoryDateGroup: String, CaseIterable, Identifiable {
    case today = "Today"
    case yesterday = "Yesterday"
    case past7Days = "Past 7 Days"
    case past30Days = "Past 30 Days"
    case older = "Older"

    var id: String { rawValue }

    static func group(for date: Date, calendar: Calendar = .current) -> HistoryDateGroup {
        if calendar.isDateInToday(date) {
            return .today
        }
        if calendar.isDateInYesterday(date) {
            return .yesterday
        }
        let now = Date()
        let daysAgo = calendar.dateComponents([.day], from: date, to: now).day ?? 0
        if daysAgo <= 7 {
            return .past7Days
        }
        if daysAgo <= 30 {
            return .past30Days
        }
        return .older
    }
}
