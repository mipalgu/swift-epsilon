//
//  EOLSyntaxTree.swift
//  EOL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// A reference to a type as written in source text.
///
/// Type references cover the built-in types (`String`, `Sequence(String)`,
/// `Map<String, Integer>`), model types qualified by a model name
/// (`Library!Book`) and model types qualified by package names
/// (`Library!shelves::Shelf`).
public struct EOLTypeReference: Sendable, Hashable, CustomStringConvertible {
    /// The name of the model that defines the type, if one was given.
    public var model: String?

    /// The name of the type, including any `::`-separated package qualifiers.
    public var name: String

    /// The type arguments of a parameterised collection or map type.
    public var arguments: [EOLTypeReference]

    /// The source range of the reference.
    public var range: SourceRange

    /// Creates a type reference.
    ///
    /// - Parameters:
    ///   - model: The model qualifier, if any.
    ///   - name: The type name, possibly package-qualified.
    ///   - arguments: The type arguments.
    ///   - range: The source range.
    public init(model: String? = nil, name: String, arguments: [EOLTypeReference] = [], range: SourceRange) {
        self.model = model
        self.name = name
        self.arguments = arguments
        self.range = range
    }

    /// The reference as it would be written in EOL.
    public var description: String {
        var text = model.map { $0 + EOLLanguage.Symbol.bang } ?? ""
        text += name
        if !arguments.isEmpty { text += "(" + arguments.map(\.description).joined(separator: ", ") + ")" }
        return text
    }
}

/// A literal value in source text.
public enum EOLLiteral: Sendable, Hashable {
    /// A string literal.
    case string(String)
    /// An integer literal of 64 bits.
    case integer(Int64)
    /// A real literal.
    case real(Double)
    /// A Boolean literal.
    case boolean(Bool)
    /// The `null` literal.
    case undefined
}

/// One item of a collection literal.
public enum EOLCollectionItem: Sendable, Hashable {
    /// A single element.
    case element(EOLExpression)
    /// An integer range `start..end`, inclusive at both ends.
    case range(EOLExpression, EOLExpression)
}

/// An iterator variable of a first-order operation, such as `b : Book` in `select(b : Book | …)`.
public struct EOLParameter: Sendable, Hashable {
    /// The name of the parameter.
    public var name: String

    /// The declared type, if any.
    public var type: EOLTypeReference?

    /// The source range of the declaration.
    public var range: SourceRange

    /// Creates a parameter.
    ///
    /// - Parameters:
    ///   - name: The parameter name.
    ///   - type: The declared type, if any.
    ///   - range: The source range.
    public init(name: String, type: EOLTypeReference?, range: SourceRange) {
        self.name = name
        self.type = type
        self.range = range
    }
}

/// The binary operators of EOL.
public enum EOLBinaryOperator: String, Sendable, Hashable, CaseIterable {
    /// Logical conjunction.
    case and
    /// Logical disjunction.
    case or
    /// Logical exclusive disjunction.
    case xor
    /// Logical implication.
    case implies
    /// Equality (`=` or `==`).
    case equal = "="
    /// Inequality (`<>` or `!=`).
    case notEqual = "<>"
    /// Less than.
    case less = "<"
    /// Greater than.
    case greater = ">"
    /// Less than or equal.
    case lessOrEqual = "<="
    /// Greater than or equal.
    case greaterOrEqual = ">="
    /// Addition or concatenation.
    case plus = "+"
    /// Subtraction.
    case minus = "-"
    /// Multiplication.
    case times = "*"
    /// Division.
    case divide = "/"
}

/// The unary operators of EOL.
public enum EOLUnaryOperator: String, Sendable, Hashable {
    /// Logical negation.
    case not
    /// Arithmetic negation.
    case negate = "-"
}

/// An EOL expression with its source range.
public struct EOLExpression: Sendable, Hashable {
    /// The kind of expression and its operands.
    public indirect enum Kind: Sendable, Hashable {
        /// A literal value.
        case literal(EOLLiteral)
        /// A variable, or a type named without a model qualifier.
        case name(String)
        /// A type written with a model qualifier, type arguments or package path.
        case type(EOLTypeReference)
        /// An enumeration literal `Type#literal`; the type is optional.
        case enumerationLiteral(EOLTypeReference?, String)
        /// A property access `target.name`; `extended` marks `target.~name`.
        case property(target: EOLExpression, name: String, navigation: EOLNavigation, extended: Bool)
        /// An operation call `target.name(arguments)`, or a global call when the target is `nil`.
        case call(target: EOLExpression?, name: String, arguments: [EOLExpression], navigation: EOLNavigation)
        /// A first-order operation call such as `target.select(x | body)`.
        case firstOrder(
            target: EOLExpression, name: String, iterators: [EOLParameter], bodies: [EOLExpression],
            navigation: EOLNavigation)
        /// A binary operation.
        case binary(EOLBinaryOperator, EOLExpression, EOLExpression)
        /// A unary operation.
        case unary(EOLUnaryOperator, EOLExpression)
        /// A ternary conditional `condition ? whenTrue : whenFalse`.
        case conditional(EOLExpression, EOLExpression, EOLExpression)
        /// The elvis operator `value ?: fallback`.
        case elvis(EOLExpression, EOLExpression)
        /// A collection literal such as `Sequence{1..3}`.
        case collection(EOLTypeReference, [EOLCollectionItem])
        /// A map literal `Map{key = value}`.
        case map(EOLTypeReference, [EOLMapEntry])
        /// An instantiation `new Type(arguments)`.
        case new(EOLTypeReference, [EOLExpression])
        /// An item selector `target[index]`.
        case item(EOLExpression, EOLExpression)
    }

    /// The kind of expression.
    public var kind: Kind

    /// The source range of the expression.
    public var range: SourceRange

    /// Creates an expression.
    ///
    /// - Parameters:
    ///   - kind: The kind of expression.
    ///   - range: The source range.
    public init(_ kind: Kind, range: SourceRange) {
        self.kind = kind
        self.range = range
    }
}

/// A key-value entry of a map literal.
public struct EOLMapEntry: Sendable, Hashable {
    /// The key expression.
    public var key: EOLExpression
    /// The value expression.
    public var value: EOLExpression

    /// Creates a map entry.
    ///
    /// - Parameters:
    ///   - key: The key expression.
    ///   - value: The value expression.
    public init(key: EOLExpression, value: EOLExpression) {
        self.key = key
        self.value = value
    }
}

/// The navigation operator of a property or operation call.
public enum EOLNavigation: String, Sendable, Hashable {
    /// `.`, which prefers user-defined operations.
    case dot = "."
    /// `?.`, which yields undefined for an undefined receiver.
    case safeDot = "?."
    /// `->`, which prefers built-in operations.
    case arrow = "->"
}

/// The assignment operators of EOL.
public enum EOLAssignmentOperator: String, Sendable, Hashable {
    /// Plain assignment (`=` or `:=`).
    case assign = "="
    /// The special assignment `::=`, which ETL uses to resolve equivalents.
    case special = "::="
    /// Compound addition.
    case add = "+="
    /// Compound subtraction.
    case subtract = "-="
    /// Compound multiplication.
    case multiply = "*="
    /// Compound division.
    case divide = "/="
    /// Assignment only when the target is undefined.
    case ifUndefined = "?="
}

/// A sequence of statements.
public typealias EOLBlock = [EOLStatement]

/// An EOL statement with its source range.
public struct EOLStatement: Sendable, Hashable {
    /// The kind of statement and its parts.
    public indirect enum Kind: Sendable, Hashable {
        /// A variable declaration `var name : Type = value;` or `var name : new Type;`; `special`
        /// marks an initialiser written with `::=`, which ETL resolves to equivalents.
        case variable(
            name: String, type: EOLTypeReference?, creates: Bool, arguments: [EOLExpression], value: EOLExpression?,
            special: Bool)
        /// An assignment.
        case assignment(EOLExpression, EOLAssignmentOperator, EOLExpression)
        /// An expression evaluated for its effect.
        case expression(EOLExpression)
        /// A conditional.
        case `if`(EOLExpression, EOLBlock, EOLBlock?)
        /// A pre-tested loop.
        case `while`(EOLExpression, EOLBlock)
        /// A loop over a collection.
        case `for`(EOLParameter, EOLExpression, EOLBlock)
        /// A multi-way branch.
        case `switch`(EOLExpression, [EOLSwitchCase], EOLBlock?)
        /// A return, with an optional value.
        case `return`(EOLExpression?)
        /// Leaves the innermost loop.
        case `break`
        /// Leaves all enclosing loops.
        case breakAll
        /// Continues with the next iteration.
        case `continue`
        /// Raises a user error.
        case `throw`(EOLExpression?)
        /// Deletes model elements.
        case delete(EOLExpression)
        /// A nested block.
        case block(EOLBlock)
        /// Static template text (EGL).
        case templateText(String)
        /// A template output section `[%= value %]` (EGL).
        case templateOutput(EOLExpression)
    }

    /// The kind of statement.
    public var kind: Kind

    /// The source range of the statement.
    public var range: SourceRange

    /// Creates a statement.
    ///
    /// - Parameters:
    ///   - kind: The kind of statement.
    ///   - range: The source range.
    public init(_ kind: Kind, range: SourceRange) {
        self.kind = kind
        self.range = range
    }
}

/// One `case` of a `switch` statement.
public struct EOLSwitchCase: Sendable, Hashable {
    /// The value compared with the switch value.
    public var value: EOLExpression
    /// The statements of the case.
    public var body: EOLBlock

    /// Creates a case.
    ///
    /// - Parameters:
    ///   - value: The value compared with the switch value.
    ///   - body: The statements of the case.
    public init(value: EOLExpression, body: EOLBlock) {
        self.value = value
        self.body = body
    }
}

/// An annotation on a declaration.
public struct EOLAnnotation: Sendable, Hashable {
    /// The annotation name, without `@` or `$`.
    public var name: String

    /// The value of a simple annotation, if any.
    public var value: String?

    /// The expression of an executable annotation (`$pre`, `$post`), if any.
    public var expression: EOLExpression?

    /// The source range.
    public var range: SourceRange

    /// Creates an annotation.
    ///
    /// - Parameters:
    ///   - name: The annotation name.
    ///   - value: The value of a simple annotation.
    ///   - expression: The expression of an executable annotation.
    ///   - range: The source range.
    public init(name: String, value: String? = nil, expression: EOLExpression? = nil, range: SourceRange) {
        self.name = name
        self.value = value
        self.expression = expression
        self.range = range
    }
}

/// An operation declared with `operation` or `function`.
public struct EOLOperation: Sendable, Hashable {
    /// The operation name.
    public var name: String

    /// The context type, or `nil` for an operation that applies to any receiver.
    public var contextType: EOLTypeReference?

    /// The formal parameters.
    public var parameters: [EOLParameter]

    /// The declared return type, if any.
    public var returnType: EOLTypeReference?

    /// The statements of the body.
    public var body: EOLBlock

    /// The annotations written before the declaration.
    public var annotations: [EOLAnnotation]

    /// The source range of the whole declaration.
    public var range: SourceRange

    /// The source range of the name.
    public var nameRange: SourceRange

    /// The document that declares the operation.
    public var document: String?

    /// Creates an operation.
    ///
    /// - Parameters:
    ///   - name: The operation name.
    ///   - contextType: The context type, if any.
    ///   - parameters: The formal parameters.
    ///   - returnType: The declared return type, if any.
    ///   - body: The statements of the body.
    ///   - annotations: The annotations.
    ///   - range: The source range of the declaration.
    ///   - nameRange: The source range of the name.
    ///   - document: The declaring document.
    public init(
        name: String, contextType: EOLTypeReference?, parameters: [EOLParameter], returnType: EOLTypeReference?,
        body: EOLBlock, annotations: [EOLAnnotation], range: SourceRange, nameRange: SourceRange,
        document: String? = nil
    ) {
        self.name = name
        self.contextType = contextType
        self.parameters = parameters
        self.returnType = returnType
        self.body = body
        self.annotations = annotations
        self.range = range
        self.nameRange = nameRange
        self.document = document
    }

    /// Whether the operation carries a simple annotation.
    ///
    /// - Parameter name: The annotation name.
    /// - Returns: `true` if a simple annotation with that name is present.
    public func hasAnnotation(_ name: String) -> Bool {
        annotations.contains { $0.name == name && $0.expression == nil }
    }
}

/// An `import` declaration.
public struct EOLImport: Sendable, Hashable {
    /// The path of the imported module, as written.
    public var path: String

    /// The source range of the declaration.
    public var range: SourceRange

    /// Creates an import.
    ///
    /// - Parameters:
    ///   - path: The path as written.
    ///   - range: The source range.
    public init(path: String, range: SourceRange) {
        self.path = path
        self.range = range
    }
}

/// A parsed EOL module.
public struct EOLModule: Sendable, Hashable {
    /// The document the module was read from, if known.
    public var document: String?

    /// The imports, in source order.
    public var imports: [EOLImport]

    /// The operations declared in the module, in source order.
    public var operations: [EOLOperation]

    /// The statements of the main program, in source order.
    public var statements: EOLBlock

    /// Creates a module.
    ///
    /// - Parameters:
    ///   - document: The source document.
    ///   - imports: The imports.
    ///   - operations: The operations.
    ///   - statements: The main program.
    public init(
        document: String? = nil, imports: [EOLImport] = [], operations: [EOLOperation] = [], statements: EOLBlock = []
    ) {
        self.document = document
        self.imports = imports
        self.operations = operations
        self.statements = statements
    }
}
