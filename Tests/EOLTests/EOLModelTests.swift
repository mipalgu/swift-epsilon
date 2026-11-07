//
//  EOLModelTests.swift
//  EOLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import EpsilonTestSupport
import Foundation
import Testing

@testable import EOL

@Suite("EOL model access")
struct EOLModelTests {
    /// Runs a program against a fresh library model.
    private func run(_ source: String) async throws -> String {
        try await EpsilonFixtures.run(source, models: [try await EpsilonFixtures.library()])
    }

    @Test("Instances are found by unqualified and model-qualified type names")
    func allInstances() async throws {
        let output = try await run(
            """
            Book.all.size().println();
            Library!Publication.all.size().println();
            Publication.allOfType().size().println();
            Book.allInstances().collect(b | b.title).println();
            Library.allContents().size().println();
            """)
        #expect(output == "3\n4\n0\nSequence {Dune, Cosmos, Emma}\n8\n")
    }

    @Test("Attributes, defaults, enumerations and many-valued attributes are read")
    func attributes() async throws {
        let output = try await run(
            """
            var dune = Book.all.selectOne(b | b.title = 'Dune');
            dune.pages.println();
            dune.price.println();
            dune.available.println();
            Book.all.select(b | not b.available).collect(b | b.title).println();
            (dune.genre = Library!Genre#fiction).println();
            (dune.genre = Genre#science).println();
            dune.keywords.println();
            Book.all.select(b | b.genre == #fiction).size().println();
            """)
        #expect(output == "412\n9.5\ntrue\nSequence {Emma}\ntrue\nfalse\nOrderedSet {sand, spice}\n2\n")
    }

    @Test("References, opposites and containment are navigated")
    func references() async throws {
        let output = try await run(
            """
            var cosmos = Book.all.selectOne(b | b.title = 'Cosmos');
            cosmos.authors.first().name.println();
            cosmos.authors.first().books.first().title.println();
            cosmos.eContainer().name.println();
            Library.all.first().eContents().size().println();
            Author.all.collect(a | a.name).println();
            Author.all.books.title.println();
            """)
        #expect(output == "Carl Sagan\nCosmos\nCity Library\n7\nSequence {Frank Herbert, Carl Sagan, Jane Austen}\nSequence {Dune, Cosmos, Emma}\n")
    }

    @Test("Types of elements are tested by kind and by type")
    func elementTypes() async throws {
        let output = try await run(
            """
            var m = Magazine.all.first();
            m.isKindOf(Publication).println();
            m.isTypeOf(Publication).println();
            m.isTypeOf(Magazine).println();
            m.type().name.println();
            m.hasProperty('issue').println();
            m.println();
            Library.all.first().println();
            """)
        #expect(output == "true\nfalse\ntrue\nMagazine\ntrue\nMagazine\nLibrary(City Library)\n")
    }

    @Test("Operations dispatch on model types")
    func modelOperations() async throws {
        let output = try await run(
            """
            operation Publication label() : String { return 'publication ' + self.title; }
            operation Book label() : String { return 'book ' + self.title; }
            Publication.all.collect(p | p.label()).println();
            """)
        #expect(output == "Sequence {book Dune, book Cosmos, book Emma, publication Nature Weekly}\n")
    }

    @Test("New elements are created, initialised and contained")
    func creation() async throws {
        let library = try await EpsilonFixtures.library()
        let output = try await EpsilonFixtures.run(
            """
            var lib = Library.all.first();
            var b : new Book;
            b.title = 'Solaris';
            b.pages = 204;
            b.price = 11;
            b.genre = Genre#science;
            lib.items.add(b);
            var m = new Magazine(title = 'Quarterly', issue = 2);
            lib.items.add(m);
            lib.items.size().println();
            b.eContainer().name.println();
            b.price.println();
            Book.all.selectOne(x | x.title = 'Solaris').genre.println();
            Library.allContents().size().println();
            """, models: [library])
        #expect(output == "6\nCity Library\n11.0\nscience\n10\n")
    }

    @Test("Assigning a collection to a many-valued feature replaces it and keeps opposites in step")
    func referenceAssignment() async throws {
        let output = try await run(
            """
            var dune = Book.all.first();
            var carl = Author.all.selectOne(a | a.name = 'Carl Sagan');
            dune.authors = Sequence{carl};
            carl.books.collect(b | b.title).println();
            Author.all.first().books.size().println();
            dune.authors.add(Author.all.first());
            Author.all.first().books.size().println();
            """)
        #expect(output == "Sequence {Cosmos, Dune}\n0\n1\n")
    }

    @Test("Moving an element to another container removes it from the first")
    func containmentMove() async throws {
        let output = try await run(
            """
            var lib = Library.all.first();
            var other = new Library;
            other.name = 'Branch';
            var emma = Book.all.selectOne(b | b.title = 'Emma');
            other.items.add(emma);
            lib.items.size().println();
            emma.eContainer().name.println();
            """)
        #expect(output == "3\nBranch\n")
    }

    @Test("Deleting an element removes it, its contents and references to it")
    func deletion() async throws {
        let output = try await run(
            """
            var emma = Book.all.selectOne(b | b.title = 'Emma');
            var jane = emma.authors.first();
            delete emma;
            Book.all.size().println();
            jane.books.size().println();
            Library.all.first().items.size().println();
            """)
        #expect(output == "2\n0\n3\n")
    }

    @Test("Model errors are reported with codes", arguments: [
        ("Book.all.first().colour.println();", EOLDiagnosticCode.unknownProperty),
        ("Book.all.first().pages = 'many';", .typeMismatch),
        ("Book.all.first().authors = Sequence{Book.all.first()};", .typeMismatch),
        ("var p = new Publication;", .typeMismatch),
        ("Nowhere!Book.all.println();", .unresolvedType),
        ("Library!Shelf.all.println();", .unresolvedType),
        ("Book.all.first().genre = 'romance';", .typeMismatch),
    ])
    func modelErrors(source: String, code: EOLDiagnosticCode) async throws {
        let error = await EpsilonFixtures.failure(source, models: [try await EpsilonFixtures.library()])
        #expect(error?.code == code.rawValue, "\(String(describing: error))")
        #expect(error?.range != nil)
    }

    @Test("Two models with different metamodels are kept apart")
    func multipleModels() async throws {
        let resourceSet = ResourceSet()
        let library = try await EpsilonFixtures.library(in: resourceSet)
        let tree = try await EpsilonFixtures.tree(in: resourceSet)
        let output = try await EpsilonFixtures.run(
            """
            Tree!Tree.all.size().println();
            Tree!Leaf.all.collect(l | l.label).println();
            Book.all.first().isKindOf(Tree!Tree).println();
            Tree.all.first().children.first().children.size().println();
            """, models: [library, tree])
        #expect(output == "5\nSequence {a1, a2, b}\nfalse\n2\n")
    }

    @Test("Model changes can be saved with ModelIO")
    func saving() async throws {
        let library = try await EpsilonFixtures.library()
        _ = try await EpsilonFixtures.run("Book.all.first().title = 'Dune Messiah';", models: [library])
        var diagnostics = ConversionDiagnostics()
        let text = try await ModelIO.serialise(library.resource, format: .xmi, diagnostics: &diagnostics)
        #expect(text.contains("Dune Messiah"))
    }
}
