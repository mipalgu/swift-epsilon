# Understanding EGL

How templates are rendered, how protected regions are merged, how EGX rules generate files, and which constructs are supported.

## Overview

EGL templates mix static text with EOL code (Rose, Paige, Kolovos and Polack,
"The Epsilon Generation Language", ECMDA-FA 2008). EGX adds rules that apply a
template to each element of a model and write the result to a file. Their
semantics follow the Epsilon documentation; where the documentation leaves a
detail open, the choice made here is stated.

## Template syntax

A template contains static text, code sections `[% … %]`, output sections
`[%= … %]` and comments `[* … *]`. A code section or comment that stands alone
on its line is removed together with its indentation and line break, so control
statements leave no blank lines. The outdenting close `-%]` is accepted and
behaves like `%]`.

Code writes to the output buffer `out` with `print`, `println`, `chop`,
`setContentType`, `preserve`, `startPreserve` and `stopPreserve`
(``EGLOutputBuffer``). Operations annotated `@template` return their text instead
of appending it to the output. A template sees global variables and the
variables passed to the runner, but not the caller's local variables.

## Protected regions

A protected region is delimited by marker lines in the comment style of the
generated language:

```
// protected region id on begin
… hand-written code …
// protected region id end
```

`setContentType` selects the comment style (Java, Swift, HTML, XML, EGL or Perl).
`out.preserve(id, enabled, default)` writes a complete region, and
`startPreserve` and `stopPreserve` enclose template text in one.

``EGLProtectedRegions/merge(generated:existing:document:)`` merges regenerated
text with the current file: each region of the new text that is enabled in the
existing file takes the existing start marker and contents, and all other text
comes from the new output. A region marked `off` is regenerated. Enabled
regions of the existing file whose contents the new text no longer has are
reported as warnings, because their contents are lost.

## EGX rules

An EGX rule has the form
`rule Name transform x : Type (in : collection)? { … }`. It applies to direct
instances of its type, to instances of subtypes as well when annotated `@greedy`,
or to the elements of an explicit `in` collection. For each element, the
following properties are evaluated in order, each written as `: expression` or
as a block:

1. `guard` decides whether the element is processed.
2. `pre` runs before generation.
3. `parameters` gives a map of variables for the template.
4. `template` names the template to render.
5. `target` gives the path of the file to write; without one, the text is
   generated but not written.
6. `overwrite` (default true) decides whether an existing file is replaced.
7. `merge` (default true) decides whether protected regions of the existing file
   are kept.
8. `post` runs afterwards, with the variable `generated` holding the target path,
   or the text when there is no target.

Each application is reported as an ``EGXGeneratedFile`` with a status of created,
updated, unchanged, skipped or not written. ``EGXDirectoryFileSystem`` rejects
paths that lead outside its directory unless this is explicitly allowed.

## Supported constructs

| Construct | Status | Notes |
|:--|:--|:--|
| `[% %]`, `[%= %]`, `[* *]` | Supported | A line holding only a code section or comment is removed with its line break. |
| `-%]` outdentation | Partial | Accepted, but behaves like `%]`. |
| `out.print`, `println`, `chop`, `setContentType` | Supported | Content types include Java, Swift, HTML, XML, EGL and Perl. |
| `out.preserve`, `startPreserve`, `stopPreserve` | Supported | `// protected region id on begin` … `// protected region id end`; merging keeps enabled regions of the existing file. |
| `@template` operations | Partial | Return their text; dispatch takes the first applicable operation. |
| EGX `rule … transform x : T (in : c)? { guard, pre, parameters, template, target, overwrite, merge, post }` | Supported | Properties as expressions or blocks; `generated` in `post` holds the target path. |
| Formatters, `append`, `patch`, `prinx`, `setIndenters`, traceability | Unsupported | |

All EOL constructs are available inside code sections and EGX blocks, as listed
in the EOL documentation.

## Topics

### Essentials

- <doc:GettingStarted>
