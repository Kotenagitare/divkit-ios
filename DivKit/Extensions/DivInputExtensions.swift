import CoreFoundation
import CoreGraphics
import Foundation

import BaseUIPublic
import CommonCorePublic
import LayoutKit

extension DivInput: DivBlockModeling {
  public func makeBlock(context: DivBlockModelingContext) throws -> Block {
    try applyBaseProperties(
      to: { try makeBaseBlock(context: context) },
      context: context,
      actions: nil,
      actionAnimation: nil,
      doubleTapActions: nil,
      longTapActions: nil
    )
  }

  private func makeBaseBlock(context: DivBlockModelingContext) throws -> Block {
    let expressionResolver = context.expressionResolver
    
    let font = context.fontProvider.font(
      family: resolveFontFamily(expressionResolver) ?? "",
      weight: resolveFontWeight(expressionResolver),
      size: resolveFontSizeUnit(expressionResolver)
        .makeScaledValue(resolveFontSize(expressionResolver))
    )
    var typo = Typo(font: font).allowHeightOverrun

    let kern = CGFloat(resolveLetterSpacing(expressionResolver))
    if !kern.isApproximatelyEqualTo(0) {
      typo = typo.kerned(kern)
    }

    if let lineHeight = resolveLineHeight(expressionResolver) {
      typo = typo.with(height: CGFloat(lineHeight))
    }

    let hintValue = resolveHintText(expressionResolver) ?? ""
    let keyboardType = resolveKeyboardType(expressionResolver)

    let onFocusActions = (focus?.onFocus ?? []).map {
      $0.uiAction(context: context.actionContext)
    }
    let onBlurActions = (focus?.onBlur ?? []).map {
      $0.uiAction(context: context.actionContext)
    }

    return TextInputBlock(
      widthTrait: makeContentWidthTrait(with: context),
      heightTrait: makeContentHeightTrait(with: context),
      hint: hintValue.with(typo: typo.with(color: resolveHintColor(expressionResolver))),
      textValue: Binding<String>(context: context, name: textVariable),
      rawTextValue: mask?.makeRawVariable(context),
      textTypo: typo.with(color: resolveTextColor(expressionResolver)),
      multiLineMode: keyboardType == .multiLineText,
      inputType: keyboardType.system,
      highlightColor: resolveHighlightColor(expressionResolver),
      maxVisibleLines: resolveMaxVisibleLines(expressionResolver),
      selectAllOnFocus: resolveSelectAllOnFocus(expressionResolver),
      maskValidator: mask?.makeMaskValidator(expressionResolver),
      path: context.parentPath,
      onFocusActions: onFocusActions,
      onBlurActions: onBlurActions,
      parentScrollView: context.parentScrollView
    )
  }
}

extension DivAlignmentHorizontal {
  fileprivate var system: TextAlignment {
    switch self {
    case .left:
      return .left
    case .center:
      return .center
    case .right:
      return .right
    }
  }
}

extension DivInput.KeyboardType {
  fileprivate var system: TextInputBlock.InputType {
    switch self {
    case .singleLineText, .multiLineText:
      return .default
    case .phone:
      return .keyboard(.phonePad)
    case .number:
      return .keyboard(.decimalPad)
    case .email:
      return .keyboard(.emailAddress)
    case .uri:
      return .keyboard(.URL)
    }
  }
}

extension DivInputMask {
  fileprivate func makeMaskValidator(_ resolver: ExpressionResolver) -> MaskValidator? {
    switch self {
    case let .divFixedLengthInputMask(divFixedLengthInputMask):
      return MaskValidator(
        pattern: divFixedLengthInputMask.resolvePattern(resolver) ?? "",
        alwaysVisible: divFixedLengthInputMask.resolveAlwaysVisible(resolver),
        patternElements: divFixedLengthInputMask.patternElements
          .map { $0.makePatternElement(resolver) }
      )
    case .divCurrencyInputMask:
      return nil
    }
  }

  fileprivate func makeRawVariable(_ context: DivBlockModelingContext) -> Binding<String>? {
    switch self {
    case let .divFixedLengthInputMask(divFixedLengthInputMask):
      return .init(context: context, name: divFixedLengthInputMask.rawTextVariable)
    case .divCurrencyInputMask:
      return nil
    }
  }
}

extension DivFixedLengthInputMask.PatternElement {
  fileprivate func makePatternElement(_ resolver: ExpressionResolver) -> PatternElement {
    PatternElement(
      key: (resolveKey(resolver) ?? "").first!,
      regex: try! NSRegularExpression(pattern: resolveRegex(resolver) ?? ""),
      placeholder: resolvePlaceholder(resolver).first!
    )
  }
}
