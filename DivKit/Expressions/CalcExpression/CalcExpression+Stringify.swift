import Foundation

import CommonCorePublic

extension CalcExpression {
  @usableFromInline
  static func stringify(_ value: Any) -> String {
    switch value {
    case let bool as Bool:
      return bool.description
    case let int as Int:
      return String(int)
    case let double as Double:
      let formatter = NumberFormatter()
      if double >= 1e7 || double <= -1e7 {
        formatter.numberStyle = NumberFormatter.Style.scientific
      }
      formatter.minimumFractionDigits = 1
      formatter.maximumFractionDigits = 15
      formatter.locale = Locale(identifier: "en")
      return formatter.string(from: NSNumber(value: double))!
    case let color as RGBAColor:
      return color.argbString
    case let date as Date:
      let dateFormatter = DateFormatter()
      dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
      dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
      return dateFormatter.string(from: date)
    case let array as [AnyHashable]:
      return "[\(array.map { formatValue($0) }.joined(separator: ","))]"
    case let dict as [String: AnyHashable]:
      let properties = dict
        .keys.sorted()
        .map { "\"\($0)\":\(formatValue(dict[$0] ?? "null"))" }
        .joined(separator: ",")
      return "{\(properties)}"
    default:
      return "\(value)"
    }
  }
}

private func formatValue(_ value: Any) -> String {
  switch value {
  case let string as String:
    "\"\(string)\""
  default:
    CalcExpression.stringify(value)
  }
}
