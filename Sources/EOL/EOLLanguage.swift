//
//  EOLLanguage.swift
//  EOL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// The authoritative spellings of the Epsilon Object Language.
///
/// Every keyword, operator, built-in type name and reserved variable name that
/// the lexer, parser and interpreter recognise is defined here once, so that the
/// rest of the implementation never repeats a literal with semantic meaning.
public enum EOLLanguage {

    /// The reserved words of EOL.
    public enum Keyword {
        /// Declares a local variable.
        public static let variable = "var"
        /// Declares an extended (global) variable in some dialects; parsed like `var`.
        public static let external = "ext"
        /// Starts a conditional statement.
        public static let `if` = "if"
        /// Starts the alternative branch of a conditional.
        public static let `else` = "else"
        /// Starts a pre-tested loop.
        public static let `while` = "while"
        /// Starts a loop over a collection.
        public static let `for` = "for"
        /// Separates the iterator from the collection in a `for` loop.
        public static let `in` = "in"
        /// Starts a multi-way branch.
        public static let `switch` = "switch"
        /// Labels one branch of a `switch`.
        public static let `case` = "case"
        /// Labels the fallback branch of a `switch`.
        public static let `default` = "default"
        /// Returns from an operation or block.
        public static let `return` = "return"
        /// Leaves the innermost loop.
        public static let `break` = "break"
        /// Leaves all enclosing loops.
        public static let breakAll = "breakAll"
        /// Continues with the next iteration or falls through a `switch` case.
        public static let `continue` = "continue"
        /// Raises a user error.
        public static let `throw` = "throw"
        /// Deletes a model element.
        public static let delete = "delete"
        /// Creates an instance of a type.
        public static let new = "new"
        /// Declares an operation.
        public static let operation = "operation"
        /// Declares an operation (synonym of `operation`).
        public static let function = "function"
        /// Imports another module.
        public static let `import` = "import"
        /// Logical conjunction.
        public static let and = "and"
        /// Logical disjunction.
        public static let or = "or"
        /// Logical exclusive disjunction.
        public static let xor = "xor"
        /// Logical implication.
        public static let implies = "implies"
        /// Logical negation.
        public static let not = "not"
        /// The Boolean literal `true`.
        public static let `true` = "true"
        /// The Boolean literal `false`.
        public static let `false` = "false"
        /// The undefined value.
        public static let null = "null"
        /// Starts a transaction block (not supported).
        public static let transaction = "transaction"
        /// Aborts a transaction (not supported).
        public static let abort = "abort"

        /// All reserved words of EOL.
        public static let all: Set<String> = [
            variable, external, `if`, `else`, `while`, `for`, `in`, `switch`, `case`, `default`,
            `return`, `break`, breakAll, `continue`, `throw`, delete, new, operation, function,
            `import`, and, or, xor, implies, not, `true`, `false`, null, transaction, abort,
        ]
    }

    /// The names of the built-in types of EOL.
    public enum TypeName {
        /// The supertype of every value.
        public static let any = "Any"
        /// Character strings.
        public static let string = "String"
        /// Whole numbers.
        public static let integer = "Integer"
        /// Real numbers.
        public static let real = "Real"
        /// Real numbers (alias of `Real`).
        public static let double = "Double"
        /// Real numbers (alias of `Real`).
        public static let float = "Float"
        /// Whole numbers (alias of `Integer`).
        public static let long = "Long"
        /// Truth values.
        public static let boolean = "Boolean"
        /// The abstract supertype of all collections.
        public static let collection = "Collection"
        /// Ordered collections that allow duplicates.
        public static let sequence = "Sequence"
        /// Ordered collections that allow duplicates (alias of `Sequence`).
        public static let list = "List"
        /// Unordered collections without duplicates.
        public static let set = "Set"
        /// Ordered collections without duplicates.
        public static let orderedSet = "OrderedSet"
        /// Unordered collections that allow duplicates.
        public static let bag = "Bag"
        /// Key-value maps.
        public static let map = "Map"
        /// Java objects, which are not supported.
        public static let native = "Native"
        /// The type of model types.
        public static let modelElementType = "ModelElementType"
    }

    /// The spellings of operators and punctuation.
    public enum Symbol {
        /// Assignment or equality.
        public static let equals = "="
        /// Equality.
        public static let doubleEquals = "=="
        /// Inequality.
        public static let notEquals = "<>"
        /// Inequality (alternative spelling).
        public static let bangEquals = "!="
        /// Less than.
        public static let less = "<"
        /// Greater than.
        public static let greater = ">"
        /// Less than or equal.
        public static let lessOrEqual = "<="
        /// Greater than or equal.
        public static let greaterOrEqual = ">="
        /// Addition and concatenation.
        public static let plus = "+"
        /// Subtraction and negation.
        public static let minus = "-"
        /// Multiplication.
        public static let times = "*"
        /// Division.
        public static let divide = "/"
        /// Assignment (alternative spelling).
        public static let colonEquals = ":="
        /// The special assignment, which resolves equivalents in ETL.
        public static let specialAssign = "::="
        /// Compound addition.
        public static let plusAssign = "+="
        /// Compound subtraction.
        public static let minusAssign = "-="
        /// Compound multiplication.
        public static let timesAssign = "*="
        /// Compound division.
        public static let divideAssign = "/="
        /// Assignment only when the target is undefined.
        public static let elvisAssign = "?="
        /// Increment.
        public static let increment = "++"
        /// Decrement.
        public static let decrement = "--"
        /// Navigation, preferring user-defined operations.
        public static let dot = "."
        /// Navigation that yields undefined for an undefined receiver.
        public static let safeDot = "?."
        /// Navigation, preferring built-in operations.
        public static let arrow = "->"
        /// The range operator inside collection literals.
        public static let range = ".."
        /// The model qualifier in `Model!Type`.
        public static let bang = "!"
        /// The package separator in `pkg::Type`.
        public static let packageSeparator = "::"
        /// The type annotation separator.
        public static let colon = ":"
        /// The ternary condition marker.
        public static let question = "?"
        /// The elvis operator.
        public static let elvis = "?:"
        /// Separates a first-order iterator from its body.
        public static let pipe = "|"
        /// Introduces an enumeration literal.
        public static let hash = "#"
        /// Introduces a simple annotation.
        public static let at = "@"
        /// Introduces an executable annotation.
        public static let dollar = "$"
        /// Introduces an extended property.
        public static let tilde = "~"
        /// Separates list items.
        public static let comma = ","
        /// Terminates a statement.
        public static let semicolon = ";"
        /// Opens a parenthesised group.
        public static let openParen = "("
        /// Closes a parenthesised group.
        public static let closeParen = ")"
        /// Opens a block or collection literal.
        public static let openBrace = "{"
        /// Closes a block or collection literal.
        public static let closeBrace = "}"
        /// Opens an item selector.
        public static let openBracket = "["
        /// Closes an item selector.
        public static let closeBracket = "]"

        /// Multi-character operators, longest first, as the lexer matches them.
        static let multiCharacter: [String] = [
            specialAssign, "==", "<>", "!=", "<=", ">=", ":=", "+=", "-=", "*=", "/=", "?=", "++",
            "--", "?.", "->", "..", "::", "?:",
        ]

        /// Single-character operators and punctuation.
        static let singleCharacter: Set<Character> = [
            "=", "<", ">", "+", "-", "*", "/", ".", "!", ":", "?", "|", "#", "@", "$", "~", ",", ";",
            "(", ")", "{", "}", "[", "]",
        ]
    }

    /// Names that the interpreter binds implicitly.
    public enum Variable {
        /// The receiver of an operation.
        public static let receiver = "self"
        /// The number of the current loop iteration, starting at one.
        public static let loopCount = "loopCount"
        /// Whether a `for` loop has more items after the current one.
        public static let hasMore = "hasMore"
        /// The result of an operation inside a `$post` annotation.
        public static let result = "_result"
    }

    /// The names of simple annotations that EOL interprets.
    public enum Annotation {
        /// Caches the result of a parameterless operation per receiver.
        public static let cached = "cached"
        /// Executable precondition annotation.
        public static let precondition = "pre"
        /// Executable postcondition annotation.
        public static let postcondition = "post"
    }

    /// Delimiters of comments and string literals.
    enum Lexical {
        /// Starts a line comment.
        static let lineComment = "//"
        /// Starts a block comment.
        static let blockCommentStart = "/*"
        /// Ends a block comment.
        static let blockCommentEnd = "*/"
        /// Introduces an escape sequence in a string literal.
        static let escape: Character = "\\"
        /// The characters that delimit string literals.
        static let quotes: Set<Character> = ["\"", "'"]
        /// The single-character escapes and the characters they denote.
        static let simpleEscapes: [Character: Character] = [
            "n": "\n", "t": "\t", "r": "\r", "b": "\u{8}", "f": "\u{c}", "\\": "\\", "'": "'",
            "\"": "\"", "0": "\0",
        ]
        /// Suffixes that mark a literal as a real number.
        static let realSuffixes: Set<Character> = ["f", "F", "d", "D"]
        /// Suffixes that mark a literal as a long integer.
        static let longSuffixes: Set<Character> = ["l", "L"]
    }
}
