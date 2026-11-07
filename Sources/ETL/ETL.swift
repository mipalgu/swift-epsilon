//
//  ETL.swift
//  ETL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EOL

/// The authoritative spellings of the Epsilon Transformation Language.
///
/// ETL extends EOL with transformation rules, `pre` and `post` blocks and the
/// operations that resolve the targets of transformed elements. Every word that
/// the ETL parser and transformer recognise is defined here once.
public enum ETLLanguage {
    /// The words that structure an ETL module.
    ///
    /// They are contextual: outside the positions where the ETL grammar expects
    /// them they remain ordinary EOL names.
    public enum Keyword {
        /// Declares a transformation rule.
        public static let rule = "rule"
        /// Introduces the source parameter of a rule.
        public static let transform = "transform"
        /// Introduces the target parameters of a rule.
        public static let to = "to"
        /// Introduces the rules that a rule extends.
        public static let extends = "extends"
        /// Introduces the guard of a rule.
        public static let `guard` = "guard"
        /// Declares a block that runs before the rules.
        public static let pre = "pre"
        /// Declares a block that runs after the rules.
        public static let post = "post"

        /// All ETL words.
        public static let all: Set<String> = [rule, transform, to, extends, `guard`, pre, post]
    }

    /// The annotations (or leading words) that modify a rule.
    public enum Annotation {
        /// The rule runs only when an equivalent of a matching element is requested.
        public static let lazy = "lazy"
        /// The rule's targets come first among the equivalents of an element.
        public static let primary = "primary"
        /// The rule does not run on its own; other rules extend it.
        public static let abstract = "abstract"
        /// The rule also matches instances of subtypes of its source type.
        public static let greedy = "greedy"

        /// All rule modifiers.
        public static let all: Set<String> = [lazy, primary, abstract, greedy]
    }

    /// The operations that ETL adds to EOL.
    public enum Operation {
        /// The first target of an element (or the first targets of a collection's elements).
        public static let equivalent = "equivalent"
        /// All targets of an element (or of each element of a collection).
        public static let equivalents = "equivalents"
    }

    /// The words that highlighting classifies as keywords in ETL source text.
    static let highlightedKeywords: Set<String> = EOLLanguage.Keyword.all.union(Keyword.all).union(Annotation.all)
}
