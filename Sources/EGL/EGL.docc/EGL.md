# ``EGL``

Generate text from Ecore models with the Epsilon Generation Language and EGX.

## Overview

EGL templates mix static text with EOL code in `[% %]` sections and output
sections `[%= %]`
([Rose et al., ECMDA-FA 2008](https://doi.org/10.1007/978-3-540-69100-6_1)). ``EGLTemplateRunner`` renders a
template, ``EGLProtectedRegions`` merges regenerated text with hand-written
protected regions, and ``EGXGenerator`` runs EGX rules that render one template
per matching element into target files.

```swift
let runner = EGLTemplateRunner(interpreter: EOLInterpreter(models: [library]))
let text = try await runner.render("[% for (b in Book.all) { %][%= b.title %]\n[% } %]")
```

The supported subset of EGL and EGX is listed in <doc:UnderstandingEGL>. Models
are loaded and programs are parsed as described in the EOL documentation.

## Related Documentation

### Command Line and Tutorials

- [swift-epsilon](https://mipalgu.github.io/swift-modelling/documentation/swift_epsilon/index.html) - the command-line tool of swift-modelling
- [Transforming Models and Generating Text with ETL and EGL](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/epsilon-02-etl-egl/index.html)
- [All tutorials](https://mipalgu.github.io/swift-modelling/tutorials/tutorials/index.html)

### Epsilon Modules

- [EOL](https://mipalgu.github.io/swift-epsilon/documentation/eol/) - the Epsilon Object Language
- [EVL](https://mipalgu.github.io/swift-epsilon/documentation/evl/) - model validation
- [ETL](https://mipalgu.github.io/swift-epsilon/documentation/etl/) - model-to-model transformation

### Related Packages

- [swift-ecore](https://mipalgu.github.io/swift-ecore/documentation/ecore/) - the Ecore metamodels and models that programs work on
- [swift-mtl](https://mipalgu.github.io/swift-mtl/) - MTL model-to-text generation
- [swift-xtend](https://mipalgu.github.io/swift-xtend/) - Xtend generators and transformations
- [swift-modelling](https://mipalgu.github.io/swift-modelling/) - command-line tools and tutorials for the whole toolkit

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:UnderstandingEGL>

### Templates

- ``EGLSyntax``
- ``EGLTemplate``
- ``EGLTemplateRunner``
- ``EGLOutputBuffer``
- ``EGLProtectedRegions``
- ``EGLProtectedRegion``

### EGX

- ``EGXSyntax``
- ``EGXModule``
- ``EGXGenerator``
- ``EGXFileSystem``
- ``EGXInMemoryFileSystem``
- ``EGXDirectoryFileSystem``
- ``EGXResult``
- ``EGXGeneratedFile``
