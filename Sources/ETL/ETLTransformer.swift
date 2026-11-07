//
//  ETLTransformer.swift
//  ETL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import EOL

/// One entry of the transformation trace: the targets a rule produced for a source element.
public struct ETLTraceLink: Hashable {
    /// The name of the rule that produced the targets.
    public let rule: String

    /// The transformed source element.
    public let source: EOLElement

    /// The target elements, in the order of the rule's target parameters.
    public let targets: [EOLElement]

    /// Creates a trace link.
    ///
    /// - Parameters:
    ///   - rule: The rule name.
    ///   - source: The source element.
    ///   - targets: The target elements.
    public init(rule: String, source: EOLElement, targets: [EOLElement]) {
        self.rule = rule
        self.source = source
        self.targets = targets
    }
}

/// The record of which rules transformed which source elements into which targets.
public final class ETLTrace {
    /// All links, in the order they were created.
    public private(set) var links: [ETLTraceLink] = []

    /// The positions in ``links`` by source element identifier.
    private var index: [EUUID: [Int]] = [:]

    /// Creates an empty trace.
    public init() {}

    /// Adds a link.
    ///
    /// - Parameter link: The link.
    func add(_ link: ETLTraceLink) {
        index[link.source.id, default: []].append(links.count)
        links.append(link)
    }

    /// The links of a source element.
    ///
    /// - Parameter source: The source element.
    /// - Returns: Its links, in creation order.
    public func links(for source: EOLElement) -> [ETLTraceLink] {
        (index[source.id] ?? []).map { links[$0] }
    }
}

/// Runs an ETL module.
///
/// A transformation runs in four phases. The `pre` blocks run first, in the
/// global scope, so their variables are visible to everything that follows.
/// Then, for every non-abstract, non-lazy rule in declaration order, each source
/// element of the rule's source type (exactly that type, or also subtypes for a
/// `@greedy` rule) whose guards hold is matched, and the rule's target elements
/// are created and recorded in the ``trace``. Next the bodies of all matches run
/// in the same order, the bodies of extended rules before the extending rule's
/// own body. Finally the `post` blocks run.
///
/// Inside rules, `equivalents()` and `equivalent()` (optionally restricted to
/// named rules) resolve source elements to their targets, running lazy rules on
/// demand, and the special assignment `::=` assigns the equivalents of its
/// right-hand side.
///
/// ```swift
/// let module = try ETLSyntax.parse(text, document: "tree2graph.etl").get()
/// let transformer = ETLTransformer(module: module, models: [tree, graph])
/// try await transformer.transform()
/// ```
public final class ETLTransformer {
    /// The module being run.
    public let module: ETLModule

    /// The interpreter that evaluates the module's EOL parts.
    public let interpreter: EOLInterpreter

    /// The transformation trace.
    public let trace = ETLTrace()

    /// The positions of the rules by name.
    private var ruleIndex: [String: Int] = [:]

    /// The resolved source type of each rule.
    private var sourceTypes: [EOLType] = []

    /// The resolved target types of each rule.
    private var targetTypes: [[EOLType]] = []

    /// The (rule, source) pairs that a lazy rule has already considered.
    private var lazilyConsidered: Set<RuleApplication> = []

    /// Whether the rules' types have been resolved.
    private var isPrepared = false

    /// A rule applied to a source element.
    private struct RuleApplication: Hashable {
        /// The position of the rule.
        let rule: Int
        /// The source element identifier.
        let source: EUUID
    }

    /// Creates a transformer with an interpreter of its own.
    ///
    /// - Parameters:
    ///   - module: The module to run.
    ///   - models: The source and target models.
    ///   - output: Where `print` and `println` write (standard output by default).
    ///   - errorOutput: Where `err` and `errln` write (standard error by default).
    ///   - moduleLoader: How imported modules are read (from files by default).
    public convenience init(
        module: ETLModule, models: [EOLModel], output: any EOLOutputStream = EOLStandardOutput(),
        errorOutput: any EOLOutputStream = EOLStandardOutput(error: true),
        moduleLoader: any EOLModuleLoading = EOLFileModuleLoader()
    ) {
        let interpreter = EOLInterpreter(models: models, output: output, errorOutput: errorOutput, moduleLoader: moduleLoader)
        self.init(module: module, interpreter: interpreter)
    }

    /// Creates a transformer that uses an existing interpreter.
    ///
    /// The transformer adds its equivalence operations to the interpreter's extensions.
    ///
    /// - Parameters:
    ///   - module: The module to run.
    ///   - interpreter: The interpreter, already holding the source and target models.
    public init(module: ETLModule, interpreter: EOLInterpreter) {
        self.module = module
        self.interpreter = interpreter
        for (position, rule) in module.rules.enumerated() where ruleIndex[rule.name] == nil {
            ruleIndex[rule.name] = position
        }
        interpreter.extensions.append(ETLEquivalenceExtension(transformer: self))
    }

    // MARK: - Running

    /// Runs the transformation.
    ///
    /// - Throws: `EOLError` if the module is inconsistent (an unknown or cyclic
    ///   `extends`, a duplicate rule, an unresolvable type), an import fails, or a
    ///   block, guard, initialiser or body raises an error.
    public func transform() async throws {
        if let problem = ETLValidation.diagnostics(for: module).first { throw EOLError(diagnostic: problem) }
        interpreter.document = module.document
        try interpreter.register(operations: module.operations, imports: module.imports, document: module.document)
        try prepare()
        for block in module.pre { try await interpreter.executeInGlobalScope(block.body) }
        var matches: [(rule: Int, source: EOLElement, targets: [EOLElement])] = []
        for (position, rule) in module.rules.enumerated() where !rule.isAbstract && !rule.isLazy {
            let candidates = try await interpreter.allInstances(of: sourceTypes[position], exact: !rule.isGreedy)
            for case .element(let source) in candidates.asElements {
                guard try await guardsHold(position, source) else { continue }
                let targets = try await createTargets(position, source)
                matches.append((position, source, targets))
            }
        }
        for match in matches { try await executeBody(match.rule, source: match.source, targets: match.targets) }
        for block in module.post { try await interpreter.execute(block.body) }
    }

    /// Resolves the source and target types of all rules.
    ///
    /// - Throws: `EOLError` at the type reference of a rule whose type cannot be
    ///   resolved or is not a model class.
    private func prepare() throws {
        guard !isPrepared else { return }
        for rule in module.rules {
            sourceTypes.append(try modelClass(rule.source.type, of: rule))
            targetTypes.append(try rule.targets.map { try modelClass($0.parameter.type, of: rule) })
        }
        isPrepared = true
    }

    /// Resolves a parameter type of a rule, which must be a model class.
    ///
    /// - Parameters:
    ///   - reference: The type reference.
    ///   - rule: The rule that declares it.
    /// - Returns: The model class type.
    /// - Throws: `EOLError` if the type is missing, unknown or not a model class.
    private func modelClass(_ reference: EOLTypeReference?, of rule: ETLRule) throws -> EOLType {
        guard let reference else {
            throw EOLError(.invalidDeclaration, "Rule '\(rule.name)' has a parameter without a type", range: rule.range, document: rule.document)
        }
        let type: EOLType
        do {
            type = try interpreter.resolveType(reference)
        } catch let error as EOLError {
            throw EOLError(
                .unresolvedType, "Rule '\(rule.name)': \(error.message)", range: reference.range, document: rule.document)
        }
        guard case .modelClass = type else {
            throw EOLError(
                .unresolvedType, "Rule '\(rule.name)': '\(reference)' is not a model class", range: reference.range,
                document: rule.document)
        }
        return type
    }

    // MARK: - Matching

    /// Whether the guards of a rule and of the rules it extends hold for a source element.
    ///
    /// - Parameters:
    ///   - position: The position of the rule.
    ///   - source: The source element.
    /// - Returns: `true` if every guard holds.
    /// - Throws: `EOLError` if a guard fails or is not Boolean.
    private func guardsHold(_ position: Int, _ source: EOLElement) async throws -> Bool {
        let rule = module.rules[position]
        for reference in rule.extends {
            guard let superPosition = ruleIndex[reference.name] else { continue }
            if !(try await guardsHold(superPosition, source)) { return false }
        }
        guard let ruleGuard = rule.guard else { return true }
        let variables: [String: EOLValue] = [rule.source.name: .element(source)]
        switch ruleGuard {
        case .expression(let expression):
            return try await interpreter.withScope(variables) { try await interpreter.evaluateCondition(expression) }
        case .block(let block):
            let value = try await interpreter.evaluateBlock(block, variables: variables)
            guard let flag = value.booleanValue else {
                throw EOLError(.typeMismatch, "The guard of rule '\(rule.name)' must return a Boolean", range: rule.range, document: rule.document)
            }
            return flag
        }
    }

    /// Whether a rule applies to an element by type and guards.
    ///
    /// - Parameters:
    ///   - position: The position of the rule.
    ///   - source: The candidate element.
    /// - Returns: `true` if the element has the rule's source type (or a subtype for a
    ///   greedy rule) and the guards hold.
    /// - Throws: `EOLError` if a guard fails.
    private func applies(_ position: Int, to source: EOLElement) async throws -> Bool {
        let rule = module.rules[position]
        let type = sourceTypes[position]
        let value = EOLValue.element(source)
        let typeMatches = rule.isGreedy ? try await interpreter.isKind(value, of: type) : try await interpreter.isType(value, of: type)
        guard typeMatches else { return false }
        return try await guardsHold(position, source)
    }

    /// Creates (or obtains from initialisers) the targets of a rule for a source element and records the link.
    ///
    /// - Parameters:
    ///   - position: The position of the rule.
    ///   - source: The source element.
    /// - Returns: The targets, in parameter order.
    /// - Throws: `EOLError` if an initialiser does not yield an element or a class is abstract.
    private func createTargets(_ position: Int, _ source: EOLElement) async throws -> [EOLElement] {
        let rule = module.rules[position]
        var variables: [String: EOLValue] = [rule.source.name: .element(source)]
        var targets: [EOLElement] = []
        for (offset, target) in rule.targets.enumerated() {
            let element: EOLElement
            if let initialiser = target.initialiser {
                let value = try await interpreter.withScope(variables) { try await interpreter.evaluate(initialiser) }
                guard case .element(let existing) = value else {
                    throw EOLError(
                        .typeMismatch, "The initialiser of target '\(target.name)' of rule '\(rule.name)' must yield a model element",
                        range: initialiser.range, document: rule.document)
                }
                element = existing
            } else {
                guard case .modelClass(let modelClass) = targetTypes[position][offset],
                    let model = modelClass.model ?? interpreter.models.first(where: { $0.classifier(named: modelClass.eClass.name) != nil })
                else {
                    throw EOLError(
                        .unresolvedType, "No model can hold the targets of rule '\(rule.name)'", range: target.parameter.range,
                        document: rule.document)
                }
                do {
                    element = try await interpreter.createElement(of: modelClass.eClass, in: model)
                } catch let error as EOLError {
                    throw EOLError(.typeMismatch, error.message, range: target.parameter.range, document: rule.document)
                }
            }
            targets.append(element)
            variables[target.name] = .element(element)
        }
        trace.add(ETLTraceLink(rule: rule.name, source: source, targets: targets))
        return targets
    }

    /// Runs the bodies of the rules a rule extends, then the rule's own body.
    ///
    /// Each extended rule's parameters are bound positionally to the same source
    /// and target elements.
    ///
    /// - Parameters:
    ///   - position: The position of the rule.
    ///   - source: The source element.
    ///   - targets: The target elements.
    /// - Throws: `EOLError` if a body fails.
    private func executeBody(_ position: Int, source: EOLElement, targets: [EOLElement]) async throws {
        let rule = module.rules[position]
        for reference in rule.extends {
            guard let superPosition = ruleIndex[reference.name] else { continue }
            try await executeBody(superPosition, source: source, targets: targets)
        }
        var variables: [String: EOLValue] = [rule.source.name: .element(source)]
        for (target, element) in zip(rule.targets, targets) { variables[target.name] = .element(element) }
        try await interpreter.execute(rule.body, variables: variables)
    }

    // MARK: - Equivalents

    /// The targets of a source element.
    ///
    /// Applicable lazy rules (restricted to the named rules, if any) run first, once
    /// per element. The targets of primary rules come first; otherwise targets
    /// follow the declaration order of their rules.
    ///
    /// - Parameters:
    ///   - source: The source element.
    ///   - ruleNames: The rules to consider, or all rules if empty.
    /// - Returns: The targets.
    /// - Throws: `EOLError` if a rule name is unknown or a lazy rule fails.
    public func equivalents(of source: EOLElement, rules ruleNames: [String] = []) async throws -> [EOLElement] {
        try prepare()
        var allowed: Set<Int>?
        if !ruleNames.isEmpty {
            allowed = Set(
                try ruleNames.map { name -> Int in
                    guard let position = ruleIndex[name] else {
                        throw EOLError(.unknownDeclaration, "Unknown rule '\(name)'")
                    }
                    return position
                })
        }
        for (position, rule) in module.rules.enumerated() where rule.isLazy && !rule.isAbstract {
            if let allowed, !allowed.contains(position) { continue }
            try await applyLazily(position, to: source)
        }
        let links = trace.links(for: source).compactMap { link -> (Int, ETLTraceLink)? in
            guard let position = ruleIndex[link.rule] else { return nil }
            if let allowed, !allowed.contains(position) { return nil }
            return (position, link)
        }
        let ordered = links.enumerated().sorted { lhs, rhs in
            let left = module.rules[lhs.element.0].isPrimary
            let right = module.rules[rhs.element.0].isPrimary
            if left != right { return left }
            if lhs.element.0 != rhs.element.0 { return lhs.element.0 < rhs.element.0 }
            return lhs.offset < rhs.offset
        }
        return ordered.flatMap { $0.element.1.targets }
    }

    /// Runs a lazy rule on a source element if it applies and has not run on it yet.
    ///
    /// - Parameters:
    ///   - position: The position of the lazy rule.
    ///   - source: The source element.
    /// - Throws: `EOLError` if the guard, an initialiser or the body fails.
    private func applyLazily(_ position: Int, to source: EOLElement) async throws {
        guard lazilyConsidered.insert(RuleApplication(rule: position, source: source.id)).inserted else { return }
        guard try await applies(position, to: source) else { return }
        let targets = try await createTargets(position, source)
        try await executeBody(position, source: source, targets: targets)
    }
}

/// The operations that ETL adds to EOL: `equivalent`, `equivalents` and the special assignment.
final class ETLEquivalenceExtension: EOLExtension {
    /// The transformer whose trace answers the operations.
    private weak var transformer: ETLTransformer?

    /// Creates the extension.
    ///
    /// - Parameter transformer: The transformer.
    init(transformer: ETLTransformer) { self.transformer = transformer }

    /// Calls `equivalent` or `equivalents` on an element or a collection.
    ///
    /// On an element, `equivalents()` yields a sequence of its targets and
    /// `equivalent()` the first of them (or undefined). On a collection,
    /// `equivalents()` yields a bag that holds one bag of targets per element, and
    /// `equivalent()` a bag of the first target of each element that has one.
    /// String arguments restrict the rules considered.
    ///
    /// - Parameters:
    ///   - name: The operation name.
    ///   - receiver: The receiver.
    ///   - arguments: Rule names.
    ///   - interpreter: The interpreter.
    /// - Returns: The result, or `nil` for any other operation or receiver.
    /// - Throws: `EOLError` if an argument is not a rule name or a lazy rule fails.
    func call(_ name: String, on receiver: EOLValue?, arguments: [EOLValue], interpreter: EOLInterpreter) async throws
        -> EOLValue?
    {
        guard let transformer, let receiver,
            name == ETLLanguage.Operation.equivalent || name == ETLLanguage.Operation.equivalents
        else { return nil }
        let ruleNames = try arguments.map { argument -> String in
            guard let ruleName = argument.stringValue else {
                throw EOLError(.typeMismatch, "'\(name)' expects rule names as arguments")
            }
            return ruleName
        }
        let single = name == ETLLanguage.Operation.equivalent
        switch receiver {
        case .element(let element):
            let targets = try await transformer.equivalents(of: element, rules: ruleNames).map { EOLValue.element($0) }
            if single { return targets.first ?? .undefined }
            return .collection(EOLCollection(.sequence, targets))
        case .collection(let collection):
            let result = EOLCollection(.bag)
            for item in collection.elements {
                guard case .element(let element) = item else { continue }
                let targets = try await transformer.equivalents(of: element, rules: ruleNames).map { EOLValue.element($0) }
                if single {
                    if let first = targets.first { result.append(first) }
                } else {
                    result.append(.collection(EOLCollection(.bag, targets)))
                }
            }
            return .collection(result)
        default:
            return nil
        }
    }

    /// Replaces elements by their first equivalents for the special assignment `::=`.
    ///
    /// Elements without an equivalent, and values that are not elements, are kept.
    /// A collection is mapped element by element into a collection of the same kind.
    ///
    /// - Parameters:
    ///   - value: The right-hand side.
    ///   - interpreter: The interpreter.
    /// - Returns: The value to assign.
    /// - Throws: `EOLError` if a lazy rule fails.
    func specialAssignment(_ value: EOLValue, interpreter: EOLInterpreter) async throws -> EOLValue? {
        guard let transformer else { return nil }
        switch value {
        case .element(let element):
            return try await transformer.equivalents(of: element).first.map { .element($0) } ?? value
        case .collection(let collection):
            let result = EOLCollection(collection.kind)
            for item in collection.elements {
                if case .element(let element) = item, let first = try await transformer.equivalents(of: element).first {
                    result.append(.element(first))
                } else {
                    result.append(item)
                }
            }
            return .collection(result)
        default:
            return nil
        }
    }
}
