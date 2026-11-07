//
//  EGL.swift
//  EGL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

/// The authoritative spellings of the Epsilon Generation Language and of EGX.
///
/// Every keyword, variable name, output operation, content type and marker word
/// that the EGL and EGX implementations recognise is defined here once.
public enum EGLLanguage {

    /// Names that the template engine binds implicitly.
    public enum Variable {
        /// The output buffer of the running template.
        public static let out = "out"
        /// The generated file (its target path) or text, inside an EGX rule's `post` block.
        public static let generated = "generated"
    }

    /// The annotation that makes an operation return its text instead of appending it.
    public static let templateAnnotation = "template"

    /// The operations of the output buffer `out`.
    public enum Operation {
        /// Appends a value.
        public static let print = "print"
        /// Appends a value and a line break.
        public static let println = "println"
        /// Removes characters from the end of the output.
        public static let chop = "chop"
        /// Selects the comment style used by protected regions.
        public static let setContentType = "setContentType"
        /// Produces a complete protected region.
        public static let preserve = "preserve"
        /// Produces the start marker of a protected region.
        public static let startPreserve = "startPreserve"
        /// Produces the end marker of the protected region started last.
        public static let stopPreserve = "stopPreserve"
    }

    /// The words of protected region markers.
    public enum Region {
        /// The phrase that identifies a marker line.
        public static let phrase = "protected region"
        /// Marks an enabled region, whose contents survive regeneration.
        public static let on = "on"
        /// Marks a disabled region, whose contents are regenerated.
        public static let off = "off"
        /// Ends the start marker.
        public static let begin = "begin"
        /// Ends the end marker.
        public static let end = "end"
    }

    /// The comment delimiters of a content type.
    public struct CommentStyle: Sendable, Hashable {
        /// The text that opens a comment.
        public var start: String
        /// The text that closes a comment, or the empty string for line comments.
        public var end: String

        /// Creates a comment style.
        ///
        /// - Parameters:
        ///   - start: The text that opens a comment.
        ///   - end: The text that closes a comment (empty for line comments).
        public init(start: String, end: String = "") {
            self.start = start
            self.end = end
        }
    }

    /// The built-in content types and their comment styles.
    ///
    /// Names are matched without regard to case.
    public static let contentTypes: [String: CommentStyle] = [
        "java": CommentStyle(start: "//"),
        "swift": CommentStyle(start: "//"),
        "html": CommentStyle(start: "<!--", end: "-->"),
        "xml": CommentStyle(start: "<!--", end: "-->"),
        "egl": CommentStyle(start: "[*", end: "*]"),
        "perl": CommentStyle(start: "#"),
    ]

    /// The words of EGX modules.
    public enum EGXKeyword {
        /// Declares a generation rule.
        public static let rule = "rule"
        /// Introduces the element a rule transforms.
        public static let transform = "transform"
        /// Introduces an explicit domain for a rule.
        public static let `in` = "in"
        /// Declares a block that runs before the rules.
        public static let pre = "pre"
        /// Declares a block that runs after the rules.
        public static let post = "post"
        /// Limits the elements a rule applies to.
        public static let `guard` = "guard"
        /// The variables passed to the template.
        public static let parameters = "parameters"
        /// The path of the template.
        public static let template = "template"
        /// The path of the generated file.
        public static let target = "target"
        /// Whether an existing file is replaced.
        public static let overwrite = "overwrite"
        /// Whether protected regions of an existing file are kept.
        public static let merge = "merge"
        /// The annotation that makes a rule apply to instances of subtypes too.
        public static let greedy = "greedy"

        /// The properties a rule body may contain, other than `pre` and `post`.
        static let properties: Set<String> = [`guard`, parameters, template, target, overwrite, merge]
    }
}
