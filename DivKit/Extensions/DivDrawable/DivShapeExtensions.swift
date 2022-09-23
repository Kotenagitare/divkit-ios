import CoreGraphics

import CommonCore
import LayoutKit

extension DivShapeDrawable {
  func makeBlock(
    context: DivBlockModelingContext,
    widthTrait: DivDrawableWidthTrait,
    corners: CGRect.Corners
  ) throws -> Block {
    switch shape {
    case let .divRoundedRectangleShape(roundedRectangle):
      let separatorBlock: Block
      switch widthTrait {
      case .fixed:
        let width = CGFloat(
          roundedRectangle.itemWidth
            .resolveValue(context.expressionResolver) ?? 0
        )
        separatorBlock = SeparatorBlock(size: width)
      case .resizable:
        separatorBlock = SeparatorBlock()
      }
      let height = CGFloat(
        roundedRectangle
          .itemHeight
          .resolveValue(context.expressionResolver) ?? 0
      )
      let cornerRadius = CGFloat(
        roundedRectangle
          .cornerRadius
          .resolveValue(context.expressionResolver) ?? 0
      )
      let blockBorder = stroke.flatMap { BlockBorder(
        color: $0.resolveColor(context.expressionResolver) ?? .black,
        width: CGFloat($0.resolveWidth(context.expressionResolver)) / 2
      ) }
      return separatorBlock
        .addingVerticalGaps(height / 2 - 0.5)
        .addingDecorations(
          boundary: .clipCorner(radius: cornerRadius, corners: corners),
          border: blockBorder,
          backgroundColor: resolveColor(context.expressionResolver)
        )
    }
  }

  func getWidth(context: DivBlockModelingContext) -> CGFloat {
    switch shape {
    case let .divRoundedRectangleShape(rectangle):
      return CGFloat(rectangle.itemWidth.resolveValue(context.expressionResolver) ?? 0)
    }
  }

  func getHeight(context: DivBlockModelingContext) -> CGFloat {
    switch shape {
    case let .divRoundedRectangleShape(rectangle):
      let stroke = stroke?.resolveWidth(context.expressionResolver) ?? 0
      return CGFloat(
        (rectangle.itemHeight.resolveValue(context.expressionResolver) ?? 0) + stroke
      )
    }
  }
}
