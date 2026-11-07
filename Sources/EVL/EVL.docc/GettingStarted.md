# Getting Started with EVL

Add the package, parse an EVL module, validate a model and apply a fix.

## Overview

The EVL module checks the constraints and critiques of an EVL module against
models loaded with swift-ecore. This article shows how to validate a model,
read the results and apply a fix.

## Add the package

Add swift-epsilon to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-epsilon.git", branch: "main"),
]
```

Then add the `EVL` product, which includes the EOL module it builds on, to your
target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "EVL", package: "swift-epsilon"),
        .product(name: "EOL", package: "swift-epsilon"),
    ]
)
```

## Parse a module

Load the models with `EOLModel.load` as described in the EOL documentation, then
parse the validation module. ``EVLSyntax/parse(_:document:)`` recovers from errors
and reports positioned diagnostics:

```swift
import ECore
import EOL
import EVL
import Foundation

let source = """
    context Book {
      constraint LongEnough {
        check { var minimum = 400; return self.pages > minimum; }
        message : self.title + ' has only ' + self.pages + ' pages'
        fix {
          title : 'Set ' + self.title + ' to ' + (minimum + 1) + ' pages'
          do { self.pages = minimum + 1; }
        }
      }
      critique HasAuthor {
        check : self.authors.notEmpty()
        message : self.title + ' has no author'
      }
    }
    """
let parsed = EVLSyntax.parse(source, document: "library.evl")
for diagnostic in parsed.diagnostics {
    print(diagnostic.message)
}
let module = try parsed.get()
```

## Validate

``EVLValidator`` registers itself with an `EOLInterpreter` that holds the models:

```swift
let library = try await EOLModel.load(
    name: "Library",
    url: URL(fileURLWithPath: "Library.xmi"),
    metamodels: [URL(fileURLWithPath: "Library.ecore")],
    resourceSet: ResourceSet())
let validator = EVLValidator(interpreter: EOLInterpreter(models: [library]))
let result = try await validator.validate(module)
```

``EVLValidationResult/isValid`` is `true` when every constraint holds (critiques
do not count). ``EVLValidationResult/errors`` and ``EVLValidationResult/warnings``
separate unsatisfied constraints from critiques, and
``EVLValidationResult/diagnostics`` reports them all as `SourceDiagnostic`
values located at the declarations:

```swift
for failure in result.unsatisfied {
    print("\(failure.constraint): \(failure.message)")
}
```

## Apply a fix

Each ``EVLUnsatisfiedConstraint`` lists the fixes whose guards hold. Apply one
with ``EVLValidator/apply(_:)``, then validate again to confirm the repair:

```swift
if let offer = result.unsatisfied.first?.fixes.first {
    print(offer.title)
    try await validator.apply(offer)
}
```

## Next steps

- <doc:UnderstandingEVL> describes execution order, diagnostics and fixes, and
  lists the supported constructs.
