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
