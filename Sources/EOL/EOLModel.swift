//
//  EOLModel.swift
//  EOL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// A model that a program accesses by name, as in `Source!Book.all`.
///
/// A model wraps a `Resource` that holds its elements together with the
/// metamodel packages that define its types. The same resource can be bound
/// under several names by giving the model aliases.
public final class EOLModel: Hashable, CustomStringConvertible {
    /// The name by which programs refer to the model.
    public let name: String

    /// Further names by which programs may refer to the model.
    public let aliases: [String]

    /// The resource that holds the model's elements.
    public let resource: Resource

    /// The metamodel packages that define the model's types.
    public let packages: [EPackage]

    /// Creates a model.
    ///
    /// - Parameters:
    ///   - name: The name by which programs refer to the model.
    ///   - resource: The resource holding the elements.
    ///   - packages: The metamodel packages defining the types.
    ///   - aliases: Further names for the model.
    public init(name: String, resource: Resource, packages: [EPackage], aliases: [String] = []) {
        self.name = name
        self.resource = resource
        self.packages = packages
        self.aliases = aliases
    }

    /// Loads a model document with `ModelIO`.
    ///
    /// The metamodels are registered with the resource set first. When no metamodel
    /// locations are given, every metamodel already registered with the resource set
    /// is used to resolve type names.
    ///
    /// - Parameters:
    ///   - name: The name by which programs refer to the model.
    ///   - url: The location of the model document (XMI or JSON).
    ///   - metamodels: The locations of the `.ecore` documents of its metamodels.
    ///   - resourceSet: The resource set that receives the resource.
    ///   - aliases: Further names for the model.
    /// - Returns: The loaded model.
    /// - Throws: The error of the file system or of the parser.
    public static func load(
        name: String, url: URL, metamodels: [URL] = [], resourceSet: ResourceSet, aliases: [String] = []
    ) async throws -> EOLModel {
        var packages = try await ModelIO.registerMetamodels(at: metamodels, in: resourceSet)
        let loaded = try await ModelIO.load(url: url, resourceSet: resourceSet)
        if packages.isEmpty { packages = loaded.packages }
        if packages.isEmpty { packages = await registeredPackages(in: resourceSet) }
        return EOLModel(name: name, resource: loaded.resource, packages: packages, aliases: aliases)
    }

    /// Creates an empty model, for example the target of a transformation.
    ///
    /// - Parameters:
    ///   - name: The name by which programs refer to the model.
    ///   - packages: The metamodel packages defining the types.
    ///   - resourceSet: The resource set that receives the resource.
    ///   - uri: The URI of the new resource.
    ///   - aliases: Further names for the model.
    /// - Returns: The empty model.
    public static func empty(
        name: String, packages: [EPackage], resourceSet: ResourceSet, uri: String, aliases: [String] = []
    ) async -> EOLModel {
        for package in packages { await resourceSet.registerMetamodel(package) }
        let resource = await resourceSet.createResource(uri: uri)
        return EOLModel(name: name, resource: resource, packages: packages, aliases: aliases)
    }

    /// The root packages registered with a resource set.
    ///
    /// - Parameter resourceSet: The resource set.
    /// - Returns: The packages, excluding the Ecore metamodel itself.
    private static func registeredPackages(in resourceSet: ResourceSet) async -> [EPackage] {
        var packages: [EPackage] = []
        for uri in await resourceSet.getMetamodelURIs() where uri != EcoreURI.ecoreNamespace.rawValue {
            if let package = await resourceSet.getMetamodel(uri: uri) { packages.append(package) }
        }
        return packages
    }

    /// Whether the model answers to a name.
    ///
    /// - Parameter candidate: The name.
    /// - Returns: `true` if the name is the model's name or one of its aliases.
    public func answers(to candidate: String) -> Bool { candidate == name || aliases.contains(candidate) }

    /// Finds a classifier of the model's metamodel.
    ///
    /// The name may be qualified with package names separated by `::`. An
    /// unqualified name is looked up in all packages, including nested ones.
    ///
    /// - Parameter qualifiedName: The classifier name.
    /// - Returns: The classifier, or `nil` if the metamodel does not define it.
    public func classifier(named qualifiedName: String) -> (any EClassifier)? {
        let parts = qualifiedName.components(separatedBy: EOLLanguage.Symbol.packageSeparator)
        if parts.count > 1 {
            var candidates = packages
            var owner: EPackage?
            for packageName in parts.dropLast() {
                guard let package = candidates.first(where: { $0.name == packageName }) else { return nil }
                owner = package
                candidates = package.eSubpackages
            }
            return owner?.getClassifier(parts[parts.count - 1])
        }
        for package in packages {
            if let classifier = package.getClassifier(qualifiedName, includingSubpackages: true) { return classifier }
        }
        return nil
    }

    /// Whether the model shares a metamodel package with another model.
    ///
    /// - Parameter other: The other model.
    /// - Returns: `true` if both models have a package with the same namespace URI and name.
    public func sharesMetamodel(with other: EOLModel) -> Bool {
        if other === self { return true }
        let mine = Set(packages.map { $0.nsURI + "#" + $0.name })
        return other.packages.contains { mine.contains($0.nsURI + "#" + $0.name) }
    }

    /// All elements of the model in document order, including contained ones.
    ///
    /// - Returns: The elements.
    public func allElements() async -> [any EObject] {
        await resource.getAllObjectsIncludingContents()
    }

    /// The text that represents an element when printed.
    ///
    /// The text is the class name, followed by the value of a `name` attribute in
    /// parentheses when the element has one.
    ///
    /// - Parameter id: The element identifier.
    /// - Returns: The label.
    public func label(of id: EUUID) async -> String {
        guard let object = await resource.resolve(id) else { return "\(name)#\(id)" }
        let className = (object.eClass as? EClass)?.name ?? "\(object.eClass)"
        if let dynamic = object as? DynamicEObject, let label = dynamic.eGet(EOLModel.labelFeature) as? String {
            return "\(className)(\(label))"
        }
        return className
    }

    /// The feature whose value labels printed elements.
    static let labelFeature = "name"

    /// The model name.
    public var description: String { name }

    /// Compares models by identity.
    ///
    /// - Parameters:
    ///   - lhs: The first model.
    ///   - rhs: The second model.
    /// - Returns: Whether both are the same model.
    public static func == (lhs: EOLModel, rhs: EOLModel) -> Bool { lhs === rhs }

    /// Hashes the model identity.
    ///
    /// - Parameter hasher: The hasher.
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
