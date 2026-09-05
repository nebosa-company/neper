# TypeScript LLM editing card

Use this compact card for source edits. It provides the same index-first workflow as
the Neper and Rust cards used by the benchmark.

## Core syntax

```text
import { item } from "./module.js";
export interface Name { field: Type; }
export const NAME: Type = value;
export function name(arg: Type, ...): Return { ... }
const value = expression;
return expression;
```

Declarations and blocks use braces; ordinary statements end in `;`. Comments are
`//`. Functions, values, fields, and modules conventionally use `camelCase`; types
and interfaces use `PascalCase`; constants use `SCREAMING_SNAKE`. Preserve existing
annotations, type-only imports, and module resolution style. Numeric values normally
use `number`; do not introduce an unrelated branded or runtime numeric type.

ES modules use explicit imports and exports. Keep import paths and extensions as
written. Avoid casts or `any` to paper over an edit; make the updated signature and
every resolved call site agree.

For the common signature edit shape:

```text
export function adjust(reading: number, offset: number): number {
    return reading + offset;
}

// after adding gain
export function adjust(reading: number, gain: number, offset: number): number {
    return reading * gain + offset;
}

const x = adjust(41.7, 1.0, 0.25);
```

## Tool-assisted navigation

The benchmark exposes a versioned structured index with definition and resolved call
reference records. Use it to locate the target definition and every call site before
reading source. Read only those spans, edit exact occurrences, and validate that no
old call spelling remains.
