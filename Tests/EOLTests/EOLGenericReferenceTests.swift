//
//  EOLGenericReferenceTests.swift
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

@Suite("EOL references typed with generic and inherited classes")
struct EOLGenericReferenceTests {
    /// Runs a program against a fresh annotation model and a graph model with one node.
    private func run(_ source: String) async throws -> String {
        let resourceSet = ResourceSet()
        let annotations = try await EpsilonFixtures.emptyAnnotations(in: resourceSet)
        let graph = try await EpsilonFixtures.emptyGraph(in: resourceSet)
        return try await EpsilonFixtures.run(
            "var node = new Graph!Node; node.name = 'n1';\n" + source, models: [annotations, graph])
    }

    /// Loads the graph metamodel as a model whose types are the classes of Ecore.
    private func ecoreModel(in resourceSet: ResourceSet) async throws -> EOLModel {
        let loaded = try await ModelIO.load(url: EpsilonFixtures.url("Graph.ecore"), resourceSet: resourceSet)
        return EOLModel(name: "Meta", resource: loaded.resource, packages: [EcorePackage.instance])
    }

    @Test("A single-valued reference typed EObject accepts an element of another metamodel")
    func singleEObjectReference() async throws {
        let output = try await run(
            """
            var a = new Annotation;
            a.target = node;
            a.target.name.println();
            a.target = new Note;
            a.target.isKindOf(Note).println();
            """)
        #expect(output == "n1\ntrue\n")
    }

    @Test("A many-valued reference typed EObject accepts elements of different classes")
    func manyEObjectReference() async throws {
        let output = try await run(
            """
            var a = new Annotation;
            var n = new Note;
            a.targets = Sequence{node, n, a};
            a.targets.size().println();
            a.targets.add(new Annotation);
            a.targets.size().println();
            """)
        #expect(output == "3\n4\n")
    }

    @Test("Containment references typed EObject accept and contain any element")
    func containmentEObjectReference() async throws {
        let output = try await run(
            """
            var a = new Annotation;
            var n = new Note;
            n.name = 'inner';
            a.payload = n;
            a.payload.name.println();
            n.eContainer().isKindOf(Annotation).println();
            a.payloads = Sequence{new Note, new Annotation};
            a.payloads.add(new Note);
            a.payloads.size().println();
            Annotation.all.first().eContents().size().println();
            """)
        #expect(output == "inner\ntrue\n3\n4\n")
    }

    @Test("A reference typed with a class of another package accepts its subclasses")
    func crossPackageSupertype() async throws {
        let output = try await run(
            """
            var a = new Annotation;
            var n = new Note;
            n.name = 'sub';
            a.subject = n;
            a.subject.name.println();
            """)
        #expect(output == "sub\n")
    }

    @Test("References typed with specific classes still refuse unrelated elements", arguments: [
        "var a = new Annotation; a.subject = node;",
        "var a = new Annotation; a.subject = new Annotation;",
        "var a = new Annotation; a.classifier = new Note;",
    ])
    func unrelatedElementsRefused(source: String) async throws {
        let resourceSet = ResourceSet()
        let annotations = try await EpsilonFixtures.emptyAnnotations(in: resourceSet)
        let graph = try await EpsilonFixtures.emptyGraph(in: resourceSet)
        let error = await EpsilonFixtures.failure(
            "var node = new Graph!Node;\n" + source, models: [annotations, graph])
        #expect(error?.code == EOLDiagnosticCode.typeMismatch.rawValue, "\(String(describing: error))")
    }

    @Test("A reference typed with an Ecore class accepts a metamodel element of that class")
    func ecoreClassReference() async throws {
        let resourceSet = ResourceSet()
        let annotations = try await EpsilonFixtures.emptyAnnotations(in: resourceSet)
        let metamodel = try await ecoreModel(in: resourceSet)
        let output = try await EpsilonFixtures.run(
            """
            var a = new Annotation;
            var node = Meta.allContents().selectOne(c | c.isKindOf(Meta!EClass) and c.name == 'Node');
            a.classifier = node;
            a.classifier.name.println();
            a.target = node;
            a.target.name.println();
            """, models: [annotations, metamodel])
        #expect(output == "Node\nNode\n")
    }

    @Test("Every element is a kind of EObject")
    func eObjectKind() async throws {
        let resourceSet = ResourceSet()
        let annotations = try await EpsilonFixtures.emptyAnnotations(in: resourceSet)
        let metamodel = try await ecoreModel(in: resourceSet)
        let output = try await EpsilonFixtures.run(
            """
            var n = new Annotations!Note;
            n.isKindOf(Meta!EObject).println();
            n.isTypeOf(Meta!EObject).println();
            """, models: [annotations, metamodel])
        #expect(output == "true\nfalse\n")
    }
}
