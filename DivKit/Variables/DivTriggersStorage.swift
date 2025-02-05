import Foundation

import BasePublic
import LayoutKit

public final class DivTriggersStorage {
  private typealias CardTriggers = (cardId: DivCardID, items: [Item])

  private final class Item {
    let trigger: DivTrigger
    var condition = false

    init(_ trigger: DivTrigger) {
      self.trigger = trigger
    }
  }

  private var triggersByCard: [CardTriggers] = []
  private let triggersLock = RWLock()

  private let variablesStorage: DivVariablesStorage
  private let actionHandler: DivActionHandler?
  private let persistentValuesStorage: DivPersistentValuesStorage
  private let reporter: DivReporter
  private let disposePool = AutodisposePool()

  public init(
    variablesStorage: DivVariablesStorage,
    actionHandler: DivActionHandler,
    persistentValuesStorage: DivPersistentValuesStorage,
    reporter: DivReporter? = nil
  ) {
    self.variablesStorage = variablesStorage
    self.actionHandler = actionHandler
    self.persistentValuesStorage = persistentValuesStorage
    self.reporter = reporter ?? DefaultDivReporter()

    variablesStorage.addObserver { [unowned self] event in
      runActions(event: event)
    }.dispose(in: disposePool)
  }

  public func set(
    cardId: DivCardID,
    triggers: [DivTrigger]
  ) {
    let cardTriggers = (cardId, triggers.map { Item($0) })
    triggersLock.write {
      triggersByCard.removeAll { $0.cardId == cardId }
      triggersByCard.append(cardTriggers)
    }
    let variables = variablesStorage.makeVariables(for: cardId)
    runActions(
      cardTriggers: cardTriggers,
      changedVariablesNames: Set(variables.keys),
      variables: variables
    )
  }

  private func runActions(event: DivVariablesStorage.ChangeEvent) {
    var triggers: [CardTriggers] = []
    triggersLock.read {
      switch event.kind {
      case let .local(cardId, _):
        triggers = triggersByCard
          .first { $0.cardId == cardId }
          .map { [$0] } ?? []
      case .global:
        triggers = triggersByCard
      }
    }

    for cardTriggers in triggers {
      runActions(
        cardTriggers: cardTriggers,
        changedVariablesNames: event.changedVariables,
        variables: event.newValues.makeVariables(for: cardTriggers.cardId)
      )
    }
  }

  private func runActions(
    cardTriggers: CardTriggers,
    changedVariablesNames: Set<DivVariableName>,
    variables: DivVariables
  ) {
    let cardId = cardTriggers.cardId
    for item in cardTriggers.items {
      let trigger = item.trigger
      if trigger.condition.variablesNames.isDisjoint(with: changedVariablesNames) {
        continue
      }

      let oldCondition = item.condition
      let expressionResolver = ExpressionResolver(
        variables: variables,
        persistentValuesStorage: persistentValuesStorage,
        errorTracker: reporter.asExpressionErrorTracker(cardId: cardId)
      )
      item.condition = trigger.resolveCondition(expressionResolver) ?? false
      if !item.condition {
        continue
      }
      if trigger.resolveMode(expressionResolver) == .onCondition, oldCondition {
        continue
      }

      for action in trigger.actions {
        actionHandler?.handle(
          action,
          cardId: cardId,
          source: .trigger,
          sender: nil
        )
      }
    }
  }
}

extension Expression {
  fileprivate var variablesNames: Set<DivVariableName> {
    switch self {
    case let .link(link):
      Set(link.variablesNames.map(DivVariableName.init(rawValue:)))
    case .value:
      []
    }
  }
}
