import Foundation

public struct ExpressionError: LocalizedError, CustomStringConvertible {
  static func integerOverflow() -> Error {
    ExpressionError("Integer overflow.")
  }

  static func incorrectType(_ expectedType: String, _ value: AnyHashable) -> Error {
    ExpressionError(
      "Incorrect value type: expected \"\(expectedType)\", got \"\(value.actualType)\"."
    )
  }

  static func unexpectedToken(_ token: String) -> Error {
    ExpressionError("Unexpected token: \(token)")
  }

  static func unsupportedType(op: String, args: [Any]) -> Error {
    let lhs = args[0]
    let rhs = args[1]
    let message = "Failed to evaluate [\(formatArgForError(lhs)) \(op) \(formatArgForError(rhs))]."
    let lhsType = formatTypeForError(lhs)
    let rhsType = formatTypeForError(rhs)
    if lhsType == rhsType {
      return ExpressionError(
        "\(message) Operator '\(op)' cannot be applied to \(lhsType) type."
      )
    }
    return ExpressionError(
      "\(message) Operator '\(op)' cannot be applied to different types: \(lhsType) and \(rhsType)."
    )
  }

  public let description: String
  let message: String

  init(
    _ message: String,
    expression: String? = nil
  ) {
    self.message = message

    description = if let expression {
      "\(message) Expression: \(expression)"
    } else {
      message
    }
  }

  public var errorDescription: String? {
    description
  }
}
