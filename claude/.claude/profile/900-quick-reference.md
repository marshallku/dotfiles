# 900: Quick Reference Cheat Sheet

**Category:** REFERENCE (900-999)
**Last Updated:** 2025-12-04

---

## Purpose

Quick lookup for common patterns, naming conventions, and settings. Use when you need a fast reminder without reading full documentation.

---

## Naming Quick Reference

| Type | Convention | Example |
|------|-----------|---------|
| Variable | camelCase | `userName`, `postData` |
| Function | camelCase | `fetchUser`, `calculateTotal` |
| Component | PascalCase | `Button`, `UserProfile` |
| Interface/Type | PascalCase | `User`, `PostData` |
| Constant | UPPER_CASE | `API_URL`, `MAX_RETRY` |
| Private/Unused | _prefix | `_internalFn`, `_unusedVar` |
| File (component) | PascalCase | `Button.tsx`, `UserProfile.tsx` |
| File (other) | camelCase | `helpers.ts`, `dateUtils.ts` |
| Directory | lowercase | `components/`, `utils/` |

---

## Common Code Patterns Quick Reference

### TypeScript/JavaScript

```typescript
// Error handling
const [error, data] = await to(promise);

// Early returns
if (!valid) return;

// Event listeners
el.addEventListener("click", fn, { passive: true });

// Path imports
import { X } from "#utils";

// Destructuring
const { a, b, c } = object;

// Function params (3+)
function fn({ a, b, c }: Params) { }

// Type imports
import { type User } from "#types";

// Optional chaining
const x = obj?.nested?.prop ?? default;

// Array operations
items.map(x => transform(x))
     .filter(x => isValid(x))
     .slice(0, 10);
```

### Rust

```rust
// Error handling
let result = operation().map_err(|e| e.to_string())?;

// Early returns
if !valid {
    return;
}

// Pattern matching
match result {
    Ok(data) => process(data),
    Err(error) => handle_error(error),
}

// Iterators
items.iter()
     .filter(|x| is_valid(x))
     .map(|x| transform(x))
     .collect()
```

---

## ESLint/Prettier Quick Settings

```json
{
    "printWidth": 120,
    "tabWidth": 4,
    "semi": true,
    "singleQuote": false,
    "trailingComma": "all",
    "endOfLine": "auto"
}
```

**Key Points:**
- 120 characters (not 80, not 100)
- 4 spaces (not 2)
- Double quotes (not single)
- Always trailing commas
- Semicolons required

---

## The Rule of Three

**Most Important Pattern:**

- 3 repetitions â extract/refactor
- 3+ parameters â use object
- 3+ concerns â split module
- 3 = complexity threshold

---

## Import Organization

```typescript
// 1. External dependencies (alphabetical)
import { Icon } from "@external/icon";
import Link from "next/link";

// 2. Internal imports (alphabetical)
import { Component } from "#components";
import { API_URL } from "#constants";
import { type User } from "#types";

// 3. Styles last
import styles from "./index.module.scss";
```

**Rules:**
- Newlines between groups
- Alphabetical within groups
- Type imports use `type` keyword

---

## File Structure Pattern

```
project/
âââ src/
â   âââ components/
â   âââ utils/
â   â   âââ lib/           # Implementations
â   â   âââ index.ts       # Barrel export
â   âââ types/
â   â   âââ lib/
â   â   âââ index.ts
â   âââ constants/
âââ __tests__/             # Co-located tests
âââ package.json
```

---

## Component Structure (React)

```typescript
// 1. "use client" if needed
"use client";

// 2. Imports (grouped)
import { useState } from "react";
import styles from "./index.module.scss";

// 3. Types
interface Props {
    title: string;
}

// 4. Constants
const cx = classNames(styles, "component");

// 5. Component
export default function Component({ title }: Props) {
    // Hooks first
    const [state, setState] = useState();

    // Event handlers
    const handleClick = () => { };

    // Early returns
    if (!title) return null;

    // JSX
    return <div className={cx()}>{title}</div>;
}
```

---

## Decision Quick Check

When unsure:

1. â Does it follow Rule of Three?
2. â Is it clear and readable?
3. â Is it performant enough?
4. â Is it maintainable?
5. â Is the cost/benefit favorable?

If all yes â Proceed
If any no â Reconsider

---

## Common Anti-Patterns (DON'T)

â Prefix interfaces with 'I' (IUser)
â Use relative imports beyond parent (../../../utils)
â Use single quotes
â Use 2-space indentation
â Magic numbers without constants
â Nested conditionals (use early returns)

---

## Quality Gates Checklist

- [ ] Spell check passes (cspell)
- [ ] ESLint passes (no errors)
- [ ] Prettier check passes
- [ ] All tests pass
- [ ] Build succeeds
- [ ] No console.log (only warn/error)

---

## Path Aliases

**Always use # prefix:**

```typescript
// â Good
import { helper } from "#utils";
import { type User } from "#types";

// â Bad
import { helper } from "../../../utils";
```

---

## Git Commit Pattern

```bash
git commit -m "$(cat <<'EOF'
Short description of change

ð¤ Generated with Claude Code

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Quick Troubleshooting

**Issue:** Not sure which pattern to use
**Solution:** Read `020-decision-framework.md`

**Issue:** Code review rejection
**Solution:** Check `910-anti-patterns.md`

**Issue:** Starting new project
**Solution:** Read `920-project-setup.md`

**Issue:** TypeScript patterns unclear
**Solution:** Read `100-typescript-patterns.md`

---

## Remember

- **Clarity over cleverness**
- **Boring over clever**
- **Explicit over implicit**
- **Read 10x more than write**
- **Pragmatic over perfect**
- **Quality first, speed second**

---

## One-Line Reminders

- camelCase variables, PascalCase types, UPPER_CASE constants
- 120 chars, 4 spaces, double quotes, trailing commas
- # prefix for imports, early returns, destructure 3+ params
- Default async/await, exception: main().catch()
- Test what fails, skip what doesn't matter
- Optimize from experience, measure before micro-optimizing
- Refactor at 3, split at 3, extract at 3
