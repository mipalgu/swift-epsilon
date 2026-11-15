# ``EVL``

Validate Ecore models with the Epsilon Validation Language.

## Overview

EVL adds contexts, constraints, critiques and fixes to EOL. ``EVLSyntax`` parses
a module with positioned diagnostics, and ``EVLValidator`` checks the models of
an `EOLInterpreter`, reporting each unsatisfied constraint as an error and each
unsatisfied critique as a warning.

```swift
let module = try EVLSyntax.parse(source, document: "library.evl").get()
let validator = EVLValidator(interpreter: EOLInterpreter(models: [library]))
let result = try await validator.validate(module)
for diagnostic in result.diagnostics { print(diagnostic.message) }
```

The supported subset of EVL is listed in <doc:UnderstandingEVL>. Models are loaded
and programs are parsed as described in the EOL documentation.

## Related Documentation

### Command Line and Tutorials

- [swift-epsilon](https://mipalgu.github.io/swift-modelling/documentation/swift_epsilon/index.html) - the command-line tool of swift-modelling
- [Querying and Validating Models with EOL and EVL](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/epsilon-01-eol-evl/index.html)
- [All tutorials](https://mipalgu.github.io/swift-modelling/tutorials/tutorials/index.html)

### Epsilon Modules

- [EOL](https://mipalgu.github.io/swift-epsilon/documentation/eol/) - the Epsilon Object Language
- [ETL](https://mipalgu.github.io/swift-epsilon/documentation/etl/) - model-to-model transformation
- [EGL](https://mipalgu.github.io/swift-epsilon/documentation/egl/) - text generation from templates

### Related Packages

- [swift-ecore](https://mipalgu.github.io/swift-ecore/documentation/ecore/) - the Ecore metamodels and models that programs work on
- [swift-ecore OCL](https://mipalgu.github.io/swift-ecore/documentation/ocl/) - the OCL implementation that EVL constraints resemble
- [swift-modelling](https://mipalgu.github.io/swift-modelling/) - command-line tools and tutorials for the whole toolkit

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:UnderstandingEVL>

### Validating

- ``EVLSyntax``
- ``EVLValidator``
- ``EVLValidationResult``
- ``EVLUnsatisfiedConstraint``
- ``EVLFixOffer``

### Syntax Tree

- ``EVLModule``
- ``EVLContext``
- ``EVLConstraint``
- ``EVLFix``
