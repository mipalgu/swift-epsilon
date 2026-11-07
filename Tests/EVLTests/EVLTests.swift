//
//  EVLTests.swift
//  EVLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import EOL
import EpsilonTestSupport
import Testing

@testable import EVL

/// Validates the library fixture against EVL source.
private func validate(_ source: String, output: EOLStringOutput = EOLStringOutput()) async throws -> (EVLValidationResult, EVLValidator) {
    let module = try EVLSyntax.parse(source, document: "test.evl").get()
    let interpreter = EOLInterpreter(models: [try await EpsilonFixtures.library()], output: output, errorOutput: output)
    let validator = EVLValidator(interpreter: interpreter)
    return (try await validator.validate(module), validator)
}

@Suite("EVL parsing")
struct EVLParsingTests {
    static let source = """
        import 'helpers.eol';
        pre setup { var limit = 400; }
        context Book {
          guard : self.title.isDefined()
          constraint LongEnough {
            check : self.pages > limit
            message : self.title + ' is too short'
            fix {
              title : 'Pad ' + self.title
              do { self.pages = limit + 1; }
            }
          }
          @lazy
          critique Cheap {
            guard { return self.price.isDefined(); }
            check { return self.price < 10; }
          }
        }
        post { 'done'.println(); }
        operation Book isLong() : Boolean { return self.pages > 400; }
        """

    @Test("Contexts, constraints, critiques, fixes and blocks are parsed")
    func structure() throws {
        let result = EVLSyntax.parse(Self.source)
        let module = try result.get()
        #expect(module.imports.map(\.path) == ["helpers.eol"])
        #expect(module.pre.map(\.name) == ["setup"])
        #expect(module.post.count == 1)
        #expect(module.operations.map(\.name) == ["isLong"])
        let context = try #require(module.contexts.first)
        #expect(context.type.name == "Book")
        #expect(context.guardCondition != nil)
        #expect(context.constraints.map(\.name) == ["LongEnough", "Cheap"])
        #expect(context.constraints[0].fixes.count == 1)
        #expect(context.constraints[1].isCritique)
        #expect(context.constraints[1].isLazy)
        guard case .block = context.constraints[1].check else {
            Issue.record("expected a check block")
            return
        }
    }

    @Test("The outline nests constraints under their context")
    func outline() {
        let outline = EVLSyntax.parse(Self.source).outline
        let context = outline.first { $0.kind == EOLOutlineKind.context }
        #expect(context?.children.map(\.name) == ["LongEnough", "Cheap"])
        #expect(context?.children.last?.kind == EOLOutlineKind.critique)
        #expect(outline.contains { $0.kind == EOLOutlineKind.pre && $0.name == "setup" })
    }

    @Test("Highlighting treats EVL words as keywords")
    func tokens() {
        let tokens = EVLSyntax.parse("context Book { constraint C { check : true } }").tokens
        #expect(tokens.filter { $0.kind == .keyword }.count == 3)
    }

    @Test("Errors are reported with positions and parsing continues")
    func diagnostics() {
        let result = EVLSyntax.parse(
            """
            context Book {
              constraint A { check self.pages > 0 }
              constraint B { check : true }
            }
            constraint Orphan { check : true }
            context Author { constraint C { check : true } }
            """)
        #expect(result.diagnostics.count == 2)
        #expect(result.diagnostics[0].range?.start.line == 2)
        #expect(result.diagnostics[0].range?.start.column == 24)
        #expect(result.diagnostics[1].code == EOLDiagnosticCode.unsupportedConstruct.rawValue)
        #expect(result.diagnostics[1].range?.start.line == 5)
        #expect(result.module.contexts.map { $0.constraints.map(\.name) } == [["B"], ["C"]])
    }
}

@Suite("EVL validation")
struct EVLValidationTests {
    @Test("Unsatisfied constraints are errors and critiques are warnings, with messages")
    func results() async throws {
        let (result, _) = try await validate(
            """
            context Book {
              constraint LongEnough {
                check : self.pages > 400
                message : self.title + ' has only ' + self.pages + ' pages'
              }
              critique Affordable {
                check : self.price < 10
                message : self.title + ' is expensive'
              }
            }
            """)
        #expect(result.errors.map(\.message) == ["Cosmos has only 396 pages"])
        #expect(result.warnings.map(\.message) == ["Cosmos is expensive"])
        #expect(!result.isValid)
        let diagnostics = result.diagnostics
        #expect(diagnostics.map(\.severity) == [.error, .warning])
        #expect(diagnostics[0].code == EVLLanguage.unsatisfiedConstraintCode)
        #expect(diagnostics[0].range?.start.line == 2)
        #expect(diagnostics[1].code == EVLLanguage.unsatisfiedCritiqueCode)
        #expect(diagnostics[0].document == "test.evl")
    }

    @Test("A constraint without a message gets a default one")
    func defaultMessage() async throws {
        let (result, _) = try await validate("context Magazine { constraint HasIssue { check : self.issue > 10 } }")
        #expect(result.unsatisfied.map(\.message) == ["Constraint HasIssue is not satisfied for Magazine"])
    }

    @Test("Contexts apply to instances of subtypes")
    func subtypes() async throws {
        let (result, _) = try await validate("context Publication { constraint Short { check : self.title.length() < 6 } }")
        #expect(result.unsatisfied.count == 2)
        #expect(result.unsatisfied.first?.context == "Publication")
    }

    @Test("Context and constraint guards limit where constraints apply")
    func guards() async throws {
        let (result, _) = try await validate(
            """
            context Book {
              guard : self.genre = Genre#fiction
              constraint Available { check : self.available }
              constraint Cheap {
                guard { var limit = 400; return self.pages > limit; }
                check : self.price < 8
              }
            }
            """)
        #expect(result.unsatisfied.map(\.constraint) == ["Cheap", "Available"])
        #expect(result.unsatisfied.allSatisfy { $0.element.isDefined })
    }

    @Test("Variables declared in a check block are visible in the message")
    func checkVariables() async throws {
        let (result, _) = try await validate(
            """
            context Author {
              constraint Prolific {
                check { var count = self.books.size(); return count > 1; }
                message : self.name + ' wrote ' + count + ' book(s)'
              }
            }
            """)
        #expect(result.unsatisfied.map(\.message) == [
            "Frank Herbert wrote 1 book(s)", "Carl Sagan wrote 1 book(s)", "Jane Austen wrote 1 book(s)",
        ])
    }

    @Test("satisfies checks lazy constraints on demand and caches results")
    func satisfies() async throws {
        let output = EOLStringOutput()
        let (result, _) = try await validate(
            """
            context Book {
              @lazy
              constraint HasPrice { check { 'checking'.println(); return self.price.isDefined(); } }
              constraint Priced {
                guard : self.satisfies('HasPrice')
                check : self.price > 8
              }
              constraint Both { check : self.satisfiesAll('HasPrice', 'Priced') }
              constraint Either { check : self.satisfiesOne(Sequence{'Priced', 'HasPrice'}) }
            }
            """, output: output)
        #expect(output.text == "checking\nchecking\nchecking\n")
        #expect(result.unsatisfied.map(\.constraint) == ["Priced", "Both"])
    }

    @Test("Asking for an unknown constraint is an error")
    func unknownConstraint() async throws {
        await #expect(throws: EOLError.self) {
            _ = try await validate("context Book { constraint A { check : self.satisfies('Missing') } }")
        }
    }

    @Test("Pre blocks declare globals and post blocks run last")
    func preAndPost() async throws {
        let output = EOLStringOutput()
        let (result, _) = try await validate(
            """
            pre { var minimum = 400; 'pre'.println(); }
            context Book { constraint Long { check : self.pages >= minimum } }
            post { 'post'.println(); }
            """, output: output)
        #expect(output.text == "pre\npost\n")
        #expect(result.unsatisfied.count == 1)
    }

    @Test("Operations can be used in constraints")
    func operations() async throws {
        let (result, _) = try await validate(
            """
            operation Book isLong() : Boolean { return self.pages > 400; }
            context Book { constraint Long { check : self.isLong() } }
            """)
        #expect(result.unsatisfied.count == 1)
    }

    @Test("Fixes are offered with titles and repair the model when applied")
    func fixes() async throws {
        let (result, validator) = try await validate(
            """
            context Book {
              constraint LongEnough {
                check { var minimum = 400; return self.pages > minimum; }
                fix {
                  title : 'Set ' + self.title + ' to ' + (minimum + 1) + ' pages'
                  do { self.pages = minimum + 1; }
                }
                fix {
                  guard : false
                  title : 'Never offered'
                  do { }
                }
              }
            }
            """)
        let failure = try #require(result.unsatisfied.first)
        #expect(failure.fixes.map(\.title) == ["Set Cosmos to 401 pages"])
        try await validator.apply(try #require(failure.fixes.first))
        let module = try EVLSyntax.parse("context Book { constraint LongEnough { check : self.pages > 400 } }").get()
        let again = try await EVLValidator(interpreter: validator.interpreter).validate(module)
        #expect(again.isValid)
    }

    @Test("Non-Boolean checks are reported as type errors")
    func nonBoolean() async throws {
        do {
            _ = try await validate("context Book {\n  constraint Odd { check : self.pages }\n}")
            Issue.record("expected an error")
        } catch let error as EOLError {
            #expect(error.code == EOLDiagnosticCode.typeMismatch.rawValue)
        }
    }

    @Test("Run-time errors inside constraints carry positions")
    func runtimePositions() async throws {
        do {
            _ = try await validate("context Book {\n  constraint Odd {\n    check : self.colour = 'red'\n  }\n}")
            Issue.record("expected an error")
        } catch let error as EOLError {
            #expect(error.code == EOLDiagnosticCode.unknownProperty.rawValue)
            #expect(error.range?.start.line == 3)
            #expect(error.range?.start.column == 13)
        }
    }
}
