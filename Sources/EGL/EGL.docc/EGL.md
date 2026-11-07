# ``EGL``

Generate text from Ecore models with the Epsilon Generation Language and EGX.

## Overview

EGL templates mix static text with EOL code in `[% %]` sections and output
sections `[%= %]` (Rose et al., ECMDA 2008). ``EGLTemplateRunner`` renders a
template, ``EGLProtectedRegions`` merges regenerated text with hand-written
protected regions, and ``EGXGenerator`` runs EGX rules that render one template
per matching element into target files.

```swift
let runner = EGLTemplateRunner(interpreter: EOLInterpreter(models: [library]))
let text = try await runner.render("[% for (b in Book.all) { %][%= b.title %]\n[% } %]")
```

The supported subset of EGL and EGX is listed in <doc:UnderstandingEGL>. Models
are loaded and programs are parsed as described in the EOL documentation.

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
