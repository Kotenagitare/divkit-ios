//
//  CalcExpression.swift
//  Expression
//
//  Version 0.13.5
//
//  Created by Nick Lockwood on 15/09/2016.
//  Copyright © 2016 Nick Lockwood. All rights reserved.
//
//  Distributed under the permissive MIT license
//  Get the latest version from here:
//
//  https://github.com/nicklockwood/Expression
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation

import CommonCorePublic

/// Immutable wrapper for a parsed expression
/// Reusing the same CalcExpression instance for multiple evaluations is more efficient
/// than creating a new one each time you wish to evaluate an expression string
final class CalcExpression: CustomStringConvertible {
  private let root: Subexpression

  /// Evaluator for individual symbols
  typealias SymbolEvaluator = (_ args: [Value]) throws -> Value

  /// Type representing the arity (number of arguments) accepted by a function
  enum Arity: ExpressibleByIntegerLiteral, Hashable {
    /// An exact number of arguments
    case exactly(Int)

    /// A minimum number of arguments
    case atLeast(Int)

    /// Any number of arguments
    static let any = atLeast(0)

    /// ExpressibleByIntegerLiteral constructor
    init(integerLiteral value: Int) {
      self = .exactly(value)
    }

    /// No-op Hashable implementation
    /// Required to support custom Equatable implementation
    func hash(into _: inout Hasher) {}

    /// Equatable implementation
    /// Note: this works more like a contains() function if
    /// one side a range and the other is an exact value
    /// This allows foo(x) to match foo(...) in a symbols dictionary
    static func ==(lhs: Arity, rhs: Arity) -> Bool {
      lhs.matches(rhs)
    }

    func matches(_ arity: Arity) -> Bool {
      switch (self, arity) {
      case let (.exactly(lhs), .exactly(rhs)),
           let (.atLeast(lhs), .atLeast(rhs)):
        lhs == rhs
      case let (.atLeast(min), .exactly(value)),
           let (.exactly(value), .atLeast(min)):
        value >= min
      }
    }
  }

  /// Symbols that make up an expression
  enum Symbol: CustomStringConvertible, Hashable {
    /// A named variable
    case variable(String)

    /// An infix operator
    case infix(String)

    /// A prefix operator
    case prefix(String)

    /// A postfix operator
    case postfix(String)

    /// A function accepting a number of arguments specified by `arity`
    case function(String, arity: Arity)

    /// A array of values accessed by index
    case array(String)

    /// The symbol name
    var name: String {
      switch self {
      case let .variable(name),
           let .infix(name),
           let .prefix(name),
           let .postfix(name),
           let .function(name, _),
           let .array(name):
        name
      }
    }

    /// Printable version of the symbol name
    var escapedName: String {
      UnicodeScalarView(name).escapedIdentifier()
    }

    /// The human-readable description of the symbol
    var description: String {
      switch self {
      case .variable:
        "Variable \(escapedName)"
      case .infix("?:"):
        "Ternary operator ?:"
      case .infix("[]"):
        "Subscript operator []"
      case .infix:
        "Infix operator \(escapedName)"
      case .prefix:
        "Prefix operator \(escapedName)"
      case .postfix:
        "Postfix operator \(escapedName)"
      case .function:
        "Function \(escapedName)()"
      case .array:
        "Array \(escapedName)"
      }
    }
  }

  /// Alternative constructor for advanced usage
  /// Allows for dynamic symbol lookup or generation without any performance overhead
  /// Note that both math and boolean symbols are enabled by default - to disable them
  /// return `{ _ in throw CalcExpression.Error.undefinedSymbol(symbol) }` from your lookup function
  init(
    _ expression: ParsedCalcExpression,
    symbols: (Symbol) throws -> SymbolEvaluator
  ) throws {
    root = try expression.root.optimized(symbols: symbols)
  }

  /// Parse an expression.
  /// Returns an opaque struct that cannot be evaluated but can be queried
  /// for symbols or used to construct an executable CalcExpression instance
  static func parse(_ expression: String) -> ParsedCalcExpression {
    parse(UnicodeScalarView(expression.unicodeScalars))
  }

  /// Parse an expression directly from the provided UnicodeScalarView,
  /// stopping when it reaches a token matching the `delimiter` string.
  /// This is convenient if you wish to parse expressions that are nested
  /// inside another string, e.g. for implementing string interpolation.
  /// If no delimiter string is specified, the method will throw an error
  /// if it encounters an unexpected token, but won't consume it
  private static func parse(
    _ input: UnicodeScalarView,
    upTo delimiters: String...
  ) -> ParsedCalcExpression {
    var unicodeScalarView = input
    let start = unicodeScalarView
    var subexpression: Subexpression
    do {
      subexpression = try unicodeScalarView.parseSubexpression(upTo: delimiters)
    } catch {
      let expression = String(start.prefix(upTo: unicodeScalarView.startIndex))
      subexpression = .error(error as! Error, expression)
    }
    return ParsedCalcExpression(root: subexpression)
  }

  /// Returns the optmized, pretty-printed expression if it was valid
  /// Otherwise, returns the original (invalid) expression string
  var description: String { root.description }

  /// All symbols used in the expression
  var symbols: Set<Symbol> { root.symbols }

  /// Evaluate the expression
  func evaluate() throws -> Value {
    try root.evaluate()
  }
}

// MARK: Internal API

extension CalcExpression {
  // Fallback evaluator for when symbol is not found
  static func errorEvaluator(for symbol: Symbol) -> SymbolEvaluator {
    switch symbol {
    case .infix("[]"), .function("[]", _), .infix("()"):
      { _ in throw Error.unexpectedToken(String(symbol.name.prefix(1))) }
    case let .function(name, _):
      { _ in
        throw Error.message("Failed to evaluate [\(name)()]. Unknown function name: \(name).")
      }
    default:
      { _ in throw Error.undefinedSymbol(symbol) }
    }
  }
}

// MARK: Private API

extension CalcExpression {
  // https://github.com/apple/swift-evolution/blob/master/proposals/0077-operator-precedence.md
  fileprivate static let operatorPrecedence: [String: (
    precedence: Int,
    isRightAssociative: Bool
  )] = {
    var precedences = [
      "[]": 100,
      "*": 1, "/": 1, "%": 1, // multiplication
      // +, -, |, ^, etc: 0 (also the default)
      "!:": -3,
      // comparison: -4
      "&&": -5, // and
      "||": -6, // or
      ":": -8, // ternary
    ].mapValues { ($0, false) }
    precedences["?"] = (-7, true) // ternary
    for op in ["<", "<=", ">=", ">", "==", "!="] { // comparison
      precedences[op] = (-4, true)
    }
    return precedences
  }()

  fileprivate static func `operator`(_ lhs: String, takesPrecedenceOver rhs: String) -> Bool {
    let (p1, rightAssociative) = operatorPrecedence[lhs] ?? (0, false)
    let (p2, _) = operatorPrecedence[rhs] ?? (0, false)
    if p1 == p2 {
      return !rightAssociative
    }
    return p1 > p2
  }

  fileprivate static func isOperator(_ char: UnicodeScalar) -> Bool {
    // Strangely, this is faster than switching on value
    "/=­+!*%<>&|^~?:".unicodeScalars.contains(char)
  }

  fileprivate static func isIdentifierHead(_ c: UnicodeScalar) -> Bool {
    switch c.value {
    case 0x5F, // _
         0x41...0x5A, // A-Z
         0x61...0x7A: // a-z
      true
    default:
      false
    }
  }

  fileprivate static func isIdentifier(_ c: UnicodeScalar) -> Bool {
    switch c.value {
    case 0x2E, // .
         0x30...0x39: // 0-9
      true
    default:
      isIdentifierHead(c)
    }
  }
}

/// An opaque wrapper for a parsed expression
struct ParsedCalcExpression: CustomStringConvertible {
  fileprivate let root: Subexpression

  /// Returns the pretty-printed expression if it was valid
  /// Otherwise, returns the original (invalid) expression string
  var description: String { root.description }

  /// All symbols used in the expression
  var symbols: Set<CalcExpression.Symbol> { root.symbols }

  /// Any error detected during parsing
  var error: CalcExpression.Error? {
    if case let .error(error, _) = root {
      return error
    }
    return nil
  }

  var variablesNames: [String] {
    symbols
      .filter {
        guard case .variable = $0 else { return false }
        return true
      }
      .map(\.name)
  }
}

// The internal expression implementation
private enum Subexpression: CustomStringConvertible {
  case literal(CalcExpression.Value)
  case symbol(CalcExpression.Symbol, [Subexpression], CalcExpression.SymbolEvaluator?)
  case error(CalcExpression.Error, String)

  var isOperand: Bool {
    switch self {
    case let .symbol(symbol, args, _) where args.isEmpty:
      switch symbol {
      case .infix, .prefix, .postfix:
        false
      default:
        true
      }
    case .symbol, .literal:
      true
    case .error:
      false
    }
  }

  func evaluate() throws -> CalcExpression.Value {
    switch self {
    case let .literal(literal):
      return literal
    case let .symbol(symbol, args, fn):
      guard let fn else {
        return .error(CalcExpression.Error.undefinedSymbol(symbol))
      }
      do {
        return try fn(args.map { try $0.evaluate() })
      } catch {
        return .error(error)
      }
    case let .error(error, _):
      return .error(error)
    }
  }

  var description: String {
    func arguments(_ args: [Subexpression]) -> String {
      args.map(\.description)
        .joined(separator: ", ")
    }
    switch self {
    case let .literal(literal):
      return AnyCalcExpression.stringify(literal.value)
    case let .symbol(symbol, args, _):
      guard isOperand else {
        return symbol.escapedName
      }
      func needsSeparation(_ lhs: String, _ rhs: String) -> Bool {
        let lhs = lhs.unicodeScalars.last!, rhs = rhs.unicodeScalars.first!
        return (CalcExpression.isOperator(lhs) || lhs == "-")
          == (CalcExpression.isOperator(rhs) || rhs == "-")
      }
      switch symbol {
      case let .prefix(name):
        let arg = args[0]
        let description = "\(arg)"
        switch arg {
        case .symbol(.infix, _, _), .symbol(.postfix, _, _), .error,
             .symbol where needsSeparation(name, description):
          return "\(symbol.escapedName)(\(description))" // Parens required
        case .symbol, .literal:
          return "\(symbol.escapedName)\(description)" // No parens needed
        }
      case let .postfix(name):
        let arg = args[0]
        let description = "\(arg)"
        switch arg {
        case .symbol(.infix, _, _), .symbol(.postfix, _, _), .error,
             .symbol where needsSeparation(description, name):
          return "(\(description))\(symbol.escapedName)" // Parens required
        case .symbol, .literal:
          return "\(description)\(symbol.escapedName)" // No parens needed
        }
      case .infix("?:") where args.count == 3:
        return "\(args[0]) ? \(args[1]) : \(args[2])"
      case .infix("[]"):
        return "\(args[0])[\(args[1])]"
      case let .infix(name):
        let lhs = args[0]
        let lhsDescription = switch lhs {
        case let .symbol(.infix(opName), _, _)
          where !CalcExpression.operator(opName, takesPrecedenceOver: name):
          "(\(lhs))"
        default:
          "\(lhs)"
        }
        let rhs = args[1]
        let rhsDescription = switch rhs {
        case let .symbol(.infix(opName), _, _)
          where CalcExpression.operator(name, takesPrecedenceOver: opName):
          "(\(rhs))"
        default:
          "\(rhs)"
        }
        return "\(lhsDescription) \(symbol.escapedName) \(rhsDescription)"
      case .variable:
        return symbol.escapedName
      case .function("[]", _):
        return "[\(arguments(args))]"
      case .function:
        return "\(symbol.escapedName)(\(arguments(args)))"
      case .array:
        return "\(symbol.escapedName)[\(arguments(args))]"
      }
    case let .error(_, expression):
      return expression
    }
  }

  var symbols: Set<CalcExpression.Symbol> {
    switch self {
    case .literal, .error:
      return []
    case let .symbol(symbol, subexpressions, _):
      var symbols = Set([symbol])
      for subexpression in subexpressions {
        symbols.formUnion(subexpression.symbols)
      }
      return symbols
    }
  }

  func optimized(
    symbols: (CalcExpression.Symbol) throws -> CalcExpression.SymbolEvaluator
  ) throws -> Subexpression {
    guard case .symbol(let symbol, var args, _) = self else {
      return self
    }
    args = try args.map {
      try $0.optimized(symbols: symbols)
    }
    return try .symbol(symbol, args, symbols(symbol))
  }
}

// MARK: Expression parsing

// Workaround for horribly slow Substring.UnicodeScalarView perf
private struct UnicodeScalarView {
  typealias Index = String.UnicodeScalarView.Index

  private let characters: String.UnicodeScalarView
  private(set) var startIndex: Index
  private(set) var endIndex: Index

  init(_ unicodeScalars: String.UnicodeScalarView) {
    characters = unicodeScalars
    startIndex = characters.startIndex
    endIndex = characters.endIndex
  }

  init(_ unicodeScalars: Substring.UnicodeScalarView) {
    self.init(String.UnicodeScalarView(unicodeScalars))
  }

  init(_ string: String) {
    self.init(string.unicodeScalars)
  }

  var first: UnicodeScalar? {
    isEmpty ? nil : characters[startIndex]
  }

  var isEmpty: Bool {
    startIndex >= endIndex
  }

  subscript(_ index: Index) -> UnicodeScalar {
    characters[index]
  }

  func index(after index: Index) -> Index {
    characters.index(after: index)
  }

  func prefix(upTo index: Index) -> UnicodeScalarView {
    var view = UnicodeScalarView(characters)
    view.startIndex = startIndex
    view.endIndex = index
    return view
  }

  func suffix(from index: Index) -> UnicodeScalarView {
    var view = UnicodeScalarView(characters)
    view.startIndex = index
    view.endIndex = endIndex
    return view
  }

  mutating func popFirst() -> UnicodeScalar? {
    if isEmpty {
      return nil
    }
    let char = characters[startIndex]
    startIndex = characters.index(after: startIndex)
    return char
  }

  /// Returns the remaining characters
  fileprivate var unicodeScalars: Substring.UnicodeScalarView {
    characters[startIndex..<endIndex]
  }
}

private typealias _UnicodeScalarView = UnicodeScalarView
extension String {
  fileprivate init(_ unicodeScalarView: _UnicodeScalarView) {
    self.init(unicodeScalarView.unicodeScalars)
  }
}

extension Substring.UnicodeScalarView {
  fileprivate init(_ unicodeScalarView: _UnicodeScalarView) {
    self.init(unicodeScalarView.unicodeScalars)
  }
}

extension UnicodeScalarView {
  fileprivate enum Number {
    case number(String)
    case integer(String)

    var value: String {
      switch self {
      case let .number(value):
        value
      case let .integer(value):
        value
      }
    }
  }

  fileprivate mutating func scanCharacters(_ matching: (UnicodeScalar) -> Bool) -> String? {
    var index = startIndex
    while index < endIndex {
      if !matching(self[index]) {
        break
      }
      index = self.index(after: index)
    }
    if index > startIndex {
      let string = String(prefix(upTo: index))
      self = suffix(from: index)
      return string
    }
    return nil
  }

  fileprivate mutating func scanCharacter(_ matching: (UnicodeScalar) -> Bool = { _ in
    true
  }) -> String? {
    if let c = first, matching(c) {
      self = suffix(from: index(after: startIndex))
      return String(c)
    }
    return nil
  }

  fileprivate mutating func scanCharacter(_ character: UnicodeScalar) -> Bool {
    scanCharacter { $0 == character } != nil
  }

  fileprivate mutating func scanToEndOfToken() -> String? {
    scanCharacters {
      switch $0 {
      case " ", "\t", "\n", "\r":
        false
      default:
        true
      }
    }
  }

  fileprivate mutating func skipWhitespace() -> Bool {
    if let _ = scanCharacters({
      switch $0 {
      case " ", "\t", "\n", "\r":
        true
      default:
        false
      }
    }) {
      return true
    }
    return false
  }

  fileprivate mutating func parseDelimiter(_ delimiters: [String]) -> Bool {
    outer: for delimiter in delimiters {
      let start = self
      for char in delimiter.unicodeScalars {
        guard scanCharacter(char) else {
          self = start
          continue outer
        }
      }
      self = start
      return true
    }
    return false
  }

  fileprivate mutating func parseNumericLiteral() throws -> Subexpression? {
    func scanInteger() -> String? {
      scanCharacters {
        if case "0"..."9" = $0 {
          return true
        }
        return false
      }
    }

    func scanHex() -> String? {
      scanCharacters {
        switch $0 {
        case "0"..."9", "A"..."F", "a"..."f":
          true
        default:
          false
        }
      }
    }

    func scanExponent() -> String? {
      let start = self
      if let e = scanCharacter({ $0 == "e" || $0 == "E" }) {
        let sign = scanCharacter { $0 == "-" || $0 == "+" } ?? ""
        if let exponent = scanInteger() {
          return e + sign + exponent
        }
      }
      self = start
      return nil
    }

    func scanNumber() -> Number? {
      var number: Number
      var endOfInt = self
      let sign = scanCharacter { $0 == "-" } ?? ""
      if let integer = scanInteger() {
        if integer == "0", scanCharacter("x") {
          return .integer("\(sign)0x\(scanHex() ?? "")")
        }
        endOfInt = self
        if scanCharacter(".") {
          guard let fraction = scanInteger() else {
            self = endOfInt
            return .number(sign + integer)
          }
          number = .number("\(sign)\(integer).\(fraction)")
        } else {
          number = .integer(sign + integer)
        }
      } else if scanCharacter(".") {
        guard let fraction = scanInteger() else {
          self = endOfInt
          return nil
        }
        number = .number("\(sign).\(fraction)")
      } else {
        self = endOfInt
        return nil
      }
      if let exponent = scanExponent() {
        number = .number(number.value + exponent)
      }
      return number
    }

    guard let number = scanNumber() else {
      return nil
    }
    switch number {
    case let .integer(value):
      guard let result = Int(value) else {
        return .error(CalcExpression.Value.integerError(value), value)
      }
      return .literal(.integer(result))
    case let .number(value):
      guard let result = Double(value) else {
        return .error(.unexpectedToken(value), value)
      }
      return .literal(.number(result))
    }
  }

  fileprivate mutating func parseOperator() -> Subexpression? {
    if var op = scanCharacters({ $0 == "-" }) {
      if let tail = scanCharacters(CalcExpression.isOperator) {
        op += tail
      }
      return .symbol(.infix(op), [], nil)
    }
    if let op = scanCharacters(CalcExpression.isOperator) ??
      scanCharacter({ "([,".unicodeScalars.contains($0) }) {
      return .symbol(.infix(op), [], nil)
    }
    return nil
  }

  fileprivate mutating func parseIdentifier() -> Subexpression? {
    var identifier = ""
    if let head = scanCharacter(CalcExpression.isIdentifierHead) {
      identifier = head
    } else {
      return nil
    }
    while let tail = scanCharacters(CalcExpression.isIdentifier) {
      identifier += tail
    }
    if scanCharacter("'") {
      identifier.append("'")
    }
    return .symbol(.variable(identifier), [], nil)
  }

  // Note: this is not actually part of the parser, but is colocated
  // with `parseEscapedIdentifier()` because they should be updated together
  fileprivate func escapedIdentifier() -> String {
    guard let delimiter = first, "`'\"".unicodeScalars.contains(delimiter) else {
      return String(self)
    }
    var result = String(delimiter)
    var index = self.index(after: startIndex)
    while index != endIndex {
      let char = self[index]
      switch char.value {
      case 0:
        result += "\\0"
      case 9:
        result += "\\t"
      case 10:
        result += "\\n"
      case 13:
        result += "\\r"
      case 0x20..<0x7F,
           _ where CalcExpression.isOperator(char) || CalcExpression.isIdentifier(char):
        result.append(Character(char))
      default:
        result += "\\u{\(String(format: "%X", char.value))}"
      }
      index = self.index(after: index)
    }
    return result
  }

  fileprivate mutating func parseEscapedIdentifier() -> Subexpression? {
    guard let delimiter = first,
          var string = scanCharacter({ "`'\"".unicodeScalars.contains($0) })
    else {
      return nil
    }
    var part: String?
    repeat {
      part = scanCharacters { $0 != delimiter && $0 != "\\" }
      string += part ?? ""
      if scanCharacter("\\"), let c = popFirst() {
        switch c {
        case "0":
          string += "\0"
        case "t":
          string += "\t"
        case "n":
          string += "\n"
        case "r":
          string += "\r"
        case "u" where scanCharacter("{"):
          let hex = scanCharacters {
            switch $0 {
            case "0"..."9", "A"..."F", "a"..."f":
              true
            default:
              false
            }
          } ?? ""
          guard scanCharacter("}") else {
            guard let junk = scanToEndOfToken() else {
              return .error(.missingDelimiter("}"), string)
            }
            return .error(.unexpectedToken(junk), string)
          }
          guard !hex.isEmpty else {
            return .error(.unexpectedToken("}"), string)
          }
          guard let codepoint = Int(hex, safeRadix: .hex),
                let c = UnicodeScalar(codepoint)
          else {
            // TODO: better error for invalid codepoint?
            return .error(.unexpectedToken(hex), string)
          }
          string.append(Character(c))
        case "'", "\\":
          string.append(Character(c))
        case "@" where scanCharacter("{"):
          string += "@{"
        default:
          return .error(.escaping, string)
        }
        part = ""
      }
    } while part != nil
    guard scanCharacter(delimiter) else {
      return .error(
        string == String(delimiter) ?
          .unexpectedToken(string) : .missingDelimiter(String(delimiter)),
        string
      )
    }
    string.append(Character(delimiter))
    return .symbol(.variable(string), [], nil)
  }

  fileprivate mutating func parseSubexpression(upTo delimiters: [String]) throws
    -> Subexpression {
    var stack: [Subexpression] = []

    func collapseStack(from i: Int) throws {
      guard stack.count > i + 1 else {
        return
      }
      let lhs = stack[i]
      let rhs = stack[i + 1]
      if lhs.isOperand {
        if rhs.isOperand {
          guard case let .symbol(.postfix(op), args, _) = lhs else {
            // Cannot follow an operand
            throw CalcExpression.Error.unexpectedToken("\(rhs)")
          }
          // Assume postfix operator was actually an infix operator
          stack[i] = args[0]
          stack.insert(.symbol(.infix(op), [], nil), at: i + 1)
          try collapseStack(from: i)
        } else if case let .symbol(symbol, _, _) = rhs {
          switch symbol {
          case _ where stack.count <= i + 2, .postfix:
            stack[i...i + 1] = [.symbol(.postfix(symbol.name), [lhs], nil)]
            try collapseStack(from: 0)
          default:
            let rhs = stack[i + 2]
            if rhs.isOperand {
              if stack.count > i + 3 {
                switch stack[i + 3] {
                case let .symbol(.infix(op2), _, _),
                     let .symbol(.prefix(op2), _, _),
                     let .symbol(.postfix(op2), _, _):
                  guard stack.count > i + 4,
                        CalcExpression.operator(symbol.name, takesPrecedenceOver: op2)
                  else {
                    fallthrough
                  }

                default:
                  try collapseStack(from: i + 2)
                  return
                }
              }
              if symbol.name == ":",
                 case let .symbol(.infix("?"), args, _) = lhs { // ternary
                stack[i...i + 2] =
                  [.symbol(.infix("?:"), [args[0], args[1], rhs], nil)]
              } else {
                stack[i...i + 2] = [.symbol(.infix(symbol.name), [lhs, rhs], nil)]
              }
              let from = symbol.name == "?" ? i : 0
              try collapseStack(from: from)
            } else if case let .symbol(symbol2, _, _) = rhs {
              if case .prefix = symbol2 {
                try collapseStack(from: i + 2)
              } else if ["+", "/", "*"].contains(symbol.name) { // Assume infix
                stack[i + 2] = .symbol(.prefix(symbol2.name), [], nil)
                try collapseStack(from: i + 2)
              } else { // Assume postfix
                stack[i + 1] = .symbol(.postfix(symbol.name), [], nil)
                try collapseStack(from: i)
              }
            } else if case let .error(error, _) = rhs {
              throw error
            }
          }
        } else if case let .error(error, _) = rhs {
          throw error
        }
      } else if case let .symbol(symbol, _, _) = lhs {
        // Treat as prefix operator
        if rhs.isOperand {
          stack[i...i + 1] = [.symbol(.prefix(symbol.name), [rhs], nil)]
          try collapseStack(from: 0)
        } else if case .symbol = rhs {
          // Nested prefix operator?
          try collapseStack(from: i + 1)
        } else if case let .error(error, _) = rhs {
          throw error
        }
      } else if case let .error(error, _) = lhs {
        throw error
      }
    }

    func scanArguments(upTo delimiter: Unicode.Scalar) throws -> [Subexpression] {
      var args = [Subexpression]()
      if first != delimiter {
        let delimiters = [",", String(delimiter)]
        repeat {
          do {
            try args.append(parseSubexpression(upTo: delimiters))
          } catch CalcExpression.Error.unexpectedToken("") {
            if let token = scanCharacter() {
              throw CalcExpression.Error.unexpectedToken(token)
            }
          }
        } while scanCharacter(",")
      }
      guard scanCharacter(delimiter) else {
        throw CalcExpression.Error.missingDelimiter(String(delimiter))
      }
      return args
    }

    _ = skipWhitespace()
    var operandPosition = true
    var precededByWhitespace = true
    while !parseDelimiter(delimiters), let expression =
      try parseNumericLiteral() ??
      parseIdentifier() ??
      parseOperator() ??
      parseEscapedIdentifier() {
      // Prepare for next iteration
      var followedByWhitespace = skipWhitespace() || isEmpty

      func appendLiteralWithNegativeValue() {
        operandPosition = false
        if let last = stack.last, last.isOperand {
          stack.append(.symbol(.infix("+"), [], nil))
        }
        stack.append(expression)
      }

      switch expression {
      case let .symbol(.infix(name), _, _):
        switch name {
        case "(":
          switch stack.last {
          case let .symbol(.variable(name), _, _)?:
            let args = try scanArguments(upTo: ")")
            stack[stack.count - 1] =
              .symbol(.function(name, arity: .exactly(args.count)), args, nil)
          case let last? where last.isOperand:
            let args = try scanArguments(upTo: ")")
            stack[stack.count - 1] = .symbol(.infix("()"), [last] + args, nil)
          default:
            // TODO: if we make `,` a multifix operator, we can use `scanArguments()` here instead
            // Alternatively: add .function("()", arity: .any), as with []
            var subexpression = try parseSubexpression(upTo: [")"])
            switch subexpression {
            case let .literal(literal):
              switch literal {
              case let .integer(value):
                if CalcExpression.Value.minInteger <= value,
                   value <= CalcExpression.Value.maxInteger {
                  break
                } else {
                  subexpression = .error(
                    CalcExpression.Value.integerError(value),
                    expression.description
                  )
                }
              case .number, .string, .datetime, .boolean, .error:
                break
              }
            case .error, .symbol:
              break
            }
            stack.append(subexpression)
            guard scanCharacter(")") else {
              throw CalcExpression.Error.missingDelimiter(")")
            }
          }
          operandPosition = false
          followedByWhitespace = skipWhitespace()
        case ",":
          operandPosition = true
          if let last = stack.last, !last.isOperand,
             case let .symbol(.infix(op), _, _) = last {
            // If previous token was an infix operator, convert it to postfix
            stack[stack.count - 1] = .symbol(.postfix(op), [], nil)
          }
          stack.append(expression)
          operandPosition = true
          followedByWhitespace = skipWhitespace()
        case "[":
          let args = try scanArguments(upTo: "]")
          switch stack.last {
          case let .symbol(.variable(name), _, _)?:
            guard args.count == 1 else {
              throw CalcExpression.Error.arityMismatch(.array(name))
            }
            stack[stack.count - 1] = .symbol(.array(name), [args[0]], nil)
          case let last? where last.isOperand:
            guard args.count == 1 else {
              throw CalcExpression.Error.arityMismatch(.infix("[]"))
            }
            stack[stack.count - 1] = .symbol(.infix("[]"), [last, args[0]], nil)
          default:
            stack
              .append(.symbol(.function("[]", arity: .exactly(args.count)), args, nil))
          }
          operandPosition = false
          followedByWhitespace = skipWhitespace()
        default:
          switch (precededByWhitespace, followedByWhitespace) {
          case (true, true), (false, false):
            stack.append(expression)
          case (true, false):
            stack.append(.symbol(.prefix(name), [], nil))
          case (false, true):
            stack.append(.symbol(.postfix(name), [], nil))
          }
          operandPosition = true
        }
      case let .symbol(.variable(name), _, _) where !operandPosition:
        operandPosition = true
        stack.append(.symbol(.infix(name), [], nil))
      case let .literal(.integer(value)) where value < 0:
        appendLiteralWithNegativeValue()
      case let .literal(.number(value)) where value < 0:
        appendLiteralWithNegativeValue()
      default:
        operandPosition = false
        stack.append(expression)
      }

      // Next iteration
      precededByWhitespace = followedByWhitespace
    }
    // Check for trailing junk
    let start = self
    if !parseDelimiter(delimiters), let junk = scanToEndOfToken() {
      self = start
      throw CalcExpression.Error.unexpectedToken(junk)
    }
    try collapseStack(from: 0)
    switch stack.first {
    case let .error(error, _)?:
      throw error
    case let result?:
      if result.isOperand {
        return result
      }
      throw CalcExpression.Error.unexpectedToken(result.description)
    case nil:
      throw CalcExpression.Error.message("Empty expression")
    }
  }
}
