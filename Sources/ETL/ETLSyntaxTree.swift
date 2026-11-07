//
//  ETLSyntaxTree.swift
//  ETL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import EOL

/// A `pre` or `post` block of an ETL module.
public struct ETLNamedBlock: Sendable, Hashable {
    /// The optional name of the block.
    public var name: String?

    /// The statements of the block.
    public var body: EOLBlock

    /// The source range of the whole block.
    public var range: SourceRange

    /// Creates a named block.
    ///
    /// - Parameters:
    ///   - name: The optional name.
    ///   - body: The statements.
    ///   - range: The source range.
    public init(name: String?, body: EOLBlock, range: SourceRange) {
        self.name = name
        self.body = body
        self.range = range
    }
}

/// The guard of a rule, written as `guard : expression` or `guard { statements }`.
public enum ETLGuard: Sendable, Hashable {
    /// A Boolean expression.
    case expression(EOLExpression)
    /// A block that returns a Boolean.
    case block(EOLBlock)
}

/// A target parameter of a rule, such as `n : Graph!Node` or `n : Graph!Node = expression`.
public struct ETLTargetParameter: Sendable, Hashable {
    /// The parameter name and its (required) type.
    public var parameter: EOLParameter

    /// The expression that supplies an existing element instead of a new one, if any.
    public var initialiser: EOLExpression?

    /// Creates a target parameter.
    ///
    /// - Parameters:
    ///   - parameter: The name and type.
    ///   - initialiser: The optional initialiser expression.
    public init(parameter: EOLParameter, initialiser: EOLExpression? = nil) {
        self.parameter = parameter
        self.initialiser = initialiser
    }

    /// The parameter name.
    public var name: String { parameter.name }
}

/// A reference to another rule by name, as written after `extends`.
public struct ETLRuleReference: Sendable, Hashable {
    /// The referenced rule's name.
    public var name: String

    /// The source range of the name.
    public var range: SourceRange

    /// Creates a rule reference.
    ///
    /// - Parameters:
    ///   - name: The rule name.
    ///   - range: The source range.
    public init(name: String, range: SourceRange) {
        self.name = name
        self.range = range
    }
}

/// A transformation rule.
///
/// ```
/// @primary
/// rule Tree2Node
///     transform t : Tree!Tree
///     to n : Graph!Node
///     extends Base {
///     guard : t.label.isDefined()
///     n.name = t.label;
/// }
/// ```
public struct ETLRule: Sendable, Hashable {
    /// The rule name.
    public var name: String

    /// The source range of the name.
    public var nameRange: SourceRange

    /// The source parameter; its type is required.
    public var source: EOLParameter

    /// The target parameters, in declaration order.
    public var targets: [ETLTargetParameter]

    /// The rules this rule extends, in declaration order.
    public var extends: [ETLRuleReference]

    /// The guard, if any.
    public var `guard`: ETLGuard?

    /// The statements of the body.
    public var body: EOLBlock

    /// The annotations (and leading modifier words) written before the rule.
    public var annotations: [EOLAnnotation]

    /// The source range of the whole rule.
    public var range: SourceRange

    /// The document that declares the rule.
    public var document: String?

    /// Creates a rule.
    ///
    /// - Parameters:
    ///   - name: The rule name.
    ///   - nameRange: The range of the name.
    ///   - source: The source parameter.
    ///   - targets: The target parameters.
    ///   - extends: The extended rules.
    ///   - guard: The guard, if any.
    ///   - body: The body statements.
    ///   - annotations: The annotations.
    ///   - range: The range of the rule.
    ///   - document: The declaring document.
    public init(
        name: String, nameRange: SourceRange, source: EOLParameter, targets: [ETLTargetParameter],
        extends: [ETLRuleReference] = [], guard: ETLGuard? = nil, body: EOLBlock = [], annotations: [EOLAnnotation] = [],
        range: SourceRange, document: String? = nil
    ) {
        self.name = name
        self.nameRange = nameRange
        self.source = source
        self.targets = targets
        self.extends = extends
        self.guard = `guard`
        self.body = body
        self.annotations = annotations
        self.range = range
        self.document = document
    }

    /// Whether the rule carries a modifier, written as `@name` or as a leading word.
    ///
    /// - Parameter name: The modifier name.
    /// - Returns: `true` if the modifier is present.
    public func has(_ name: String) -> Bool { annotations.contains { $0.name == name } }

    /// Whether the rule runs only on demand.
    public var isLazy: Bool { has(ETLLanguage.Annotation.lazy) }

    /// Whether the rule's targets come first among equivalents.
    public var isPrimary: Bool { has(ETLLanguage.Annotation.primary) }

    /// Whether the rule only serves as a super-rule.
    public var isAbstract: Bool { has(ETLLanguage.Annotation.abstract) }

    /// Whether the rule also matches instances of subtypes.
    public var isGreedy: Bool { has(ETLLanguage.Annotation.greedy) }
}

/// A parsed ETL module.
public struct ETLModule: Sendable, Hashable {
    /// The document the module was read from, if known.
    public var document: String?

    /// The imports, in source order.
    public var imports: [EOLImport]

    /// The operations, in source order.
    public var operations: [EOLOperation]

    /// The rules, in source order.
    public var rules: [ETLRule]

    /// The `pre` blocks, in source order.
    public var pre: [ETLNamedBlock]

    /// The `post` blocks, in source order.
    public var post: [ETLNamedBlock]

    /// Creates a module.
    ///
    /// - Parameters:
    ///   - document: The source document.
    ///   - imports: The imports.
    ///   - operations: The operations.
    ///   - rules: The rules.
    ///   - pre: The `pre` blocks.
    ///   - post: The `post` blocks.
    public init(
        document: String? = nil, imports: [EOLImport] = [], operations: [EOLOperation] = [], rules: [ETLRule] = [],
        pre: [ETLNamedBlock] = [], post: [ETLNamedBlock] = []
    ) {
        self.document = document
        self.imports = imports
        self.operations = operations
        self.rules = rules
        self.pre = pre
        self.post = post
    }

    /// The rule with a name.
    ///
    /// - Parameter name: The rule name.
    /// - Returns: The first rule with that name, or `nil`.
    public func rule(named name: String) -> ETLRule? { rules.first { $0.name == name } }
}
