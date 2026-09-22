import Foundation

extension Date {
    static func dateString() -> String {
        let dateFormater = DateFormatter()
        dateFormater.dateFormat = "EEE dd MMM"
        return dateFormater.string(from: Date())
    }
    static func timeString() -> String {
        let dateFormater = DateFormatter()
        dateFormater.dateFormat = "hh:mm a"
        return dateFormater.string(from: Date())
    }
}
