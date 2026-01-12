# 910: Red Flags and Anti-Patterns

**Category:** REFERENCE (900-999)
**Last Updated:** 2025-12-04

---

## Purpose

This document lists things to **NEVER** do. Use this for code review, checking violations, and understanding what breaks the developer's coding standards.

---

## ❌ NEVER Do These

### 1. Prefixing Interfaces with 'I'

```typescript
// ❌ NEVER
interface IUser { }
interface IPost { }

// ✅ ALWAYS
interface User { }
interface Post { }
```

**Why:** This is a relic of Hungarian notation. TypeScript doesn't need this. The type itself makes it clear it's an interface or type.

---

### 2. Relative Imports Beyond Parent

```typescript
// ❌ NEVER
import { helper } from "../../../utils/helper";
import { Component } from "../../components/Button";

// ✅ ALWAYS
import { helper } from "#utils/helper";
import { Component } from "#components/Button";
```

**Why:** Relative imports become unmaintainable. Path aliases (# prefix) make refactoring easier and imports clearer.

---

### 3. Single Quote Strings

```typescript
// ❌ NEVER
const str = 'text';
const message = 'Hello';

// ✅ ALWAYS
const str = "text";
const message = "Hello";
```

**Why:** Consistency. Double quotes are the standard for this developer. Prettier enforces this.

---

### 4. 2-Space Indentation

```typescript
// ❌ NEVER
function bad() {
  return true;
}

// ✅ ALWAYS (4 spaces)
function good() {
    return true;
}
```

**Why:** 4 spaces with 120-character lines provides the right balance. 2 spaces is too compact.

---

### 5. Catch-All Error Handlers

```typescript
// ❌ NEVER (loses error context)
try {
    await operation();
} catch {
    console.log("Error occurred");
}

// ✅ ALWAYS (handle specifically)
try {
    await operation();
} catch (error) {
    console.error("Operation failed:", error);
    handleSpecificError(error);
}
```

**Why:** Empty catch blocks or generic handling lose valuable debugging information. Always log and handle errors properly.

---

### 6. Nested Conditionals

```typescript
// ❌ AVOID
function process(data) {
    if (data) {
        if (data.isValid) {
            if (!data.processed) {
                // nested logic
            }
        }
    }
}

// ✅ PREFER (early returns)
function process(data) {
    if (!data) return;
    if (!data.isValid) return;
    if (data.processed) return;

    // main logic
}
```

**Why:** Nested conditionals are hard to read and maintain. Early returns flatten the code and make the happy path clear.

---

### 7. Magic Numbers

```typescript
// ❌ AVOID
setTimeout(callback, 5000);
const chunk = data.slice(0, 20);
if (retryCount > 3) { }

// ✅ PREFER
const TIMEOUT_MS = 5000;
const CHUNK_SIZE = 20;
const MAX_RETRIES = 3;

setTimeout(callback, TIMEOUT_MS);
const chunk = data.slice(0, CHUNK_SIZE);
if (retryCount > MAX_RETRIES) { }
```

**Why:** Magic numbers lack context. Named constants make the code self-documenting.

---

### 8. Mutable Exports

```typescript
// ❌ NEVER
export let config = { };
export let state = { };

// ✅ ALWAYS
export const config = { };
export const state = { };
```

**Why:** Mutable exports make code unpredictable. Use const for exports, even for objects (object properties can still be modified if needed).

---

### 9. console.log in Production

```typescript
// ❌ NEVER (in production code)
console.log("Debug info");
console.log(data);

// ✅ ACCEPTABLE (specific cases)
console.warn("Deprecation warning");
console.error("Critical error:", error);
```

**Why:** console.log is for debugging only. Use proper logging frameworks. Only warn and error are acceptable in production.

**ESLint enforces:** `no-console: ["warn", { allow: ["warn", "error"] }]`

---

### 10. Any Type Overuse

```typescript
// ❌ AVOID
function process(data: any): any {
    return data.something;
}

// ✅ PREFER
function process(data: unknown): ProcessedData {
    if (!isValidData(data)) {
        throw new Error("Invalid data");
    }
    return processValidData(data);
}
```

**Why:** `any` defeats the purpose of TypeScript. Use `unknown` and type guards for truly dynamic data.

**Acceptable use:** When TypeScript fights you on something definitely safe, and fixing it is impractical.

---

### 11. Ignoring Linter Warnings

```typescript
// ❌ AVOID
// @ts-ignore
const result = dangerousOperation();

// eslint-disable-next-line
const unused = value;

// ✅ ONLY WHEN NECESSARY
// TODO: Update after library supports React 19
// @ts-ignore - next-mdx-remote type incompatibility
const result = operation();
```

**Why:** Linter warnings exist for a reason. If you disable them, explain why with a comment.

---

### 12. More Than 3 Function Parameters

```typescript
// ❌ NEVER
function createUser(name: string, email: string, age: number, role: string) { }

// ✅ ALWAYS (3+ → object)
function createUser({ name, email, age, role }: CreateUserParams) { }
```

**Why:** The Rule of Three. More than 3 parameters creates cognitive load. Use object destructuring.

---

### 13. Repeating Code 3+ Times

```typescript
// ❌ NEVER
const user1 = await fetch("/api/user/1").then(r => r.json());
const user2 = await fetch("/api/user/2").then(r => r.json());
const user3 = await fetch("/api/user/3").then(r => r.json());

// ✅ ALWAYS (extract after 3rd occurrence)
const fetchUser = (id: number) =>
    fetch(`/api/user/${id}`).then(r => r.json());

const user1 = await fetchUser(1);
const user2 = await fetchUser(2);
const user3 = await fetchUser(3);
```

**Why:** The Rule of Three. Third repetition is a pattern that should be extracted.

---

### 14. Hungarian Notation

```typescript
// ❌ NEVER
const strName = "John";
const intAge = 30;
const boolIsActive = true;

// ✅ ALWAYS
const name = "John";
const age = 30;
const isActive = true;
```

**Why:** TypeScript provides type information. Hungarian notation is redundant and outdated.

---

### 15. Default Exports for Utilities

```typescript
// ❌ AVOID (for utility collections)
// utils.ts
export default {
    helper1,
    helper2,
    helper3,
};

// ✅ PREFER (for utilities)
// utils.ts
export const helper1 = () => { };
export const helper2 = () => { };
export const helper3 = () => { };
```

**Why:** Named exports are better for tree-shaking and refactoring. Default exports are for main components/functions only.

---

### 16. Forgetting Passive Event Listeners

```typescript
// ❌ NEVER (performance issue)
element.addEventListener("scroll", handler);
element.addEventListener("touchmove", handler);

// ✅ ALWAYS
element.addEventListener("scroll", handler, { passive: true });
element.addEventListener("touchmove", handler, { passive: true });
```

**Why:** Performance. Scroll and touch events should be passive to avoid blocking the main thread.

---

### 17. Committing Without Testing

**❌ NEVER:**
- Commit code that doesn't build
- Commit code with failing tests
- Skip running tests before committing

**✅ ALWAYS:**
- Ensure build passes
- Ensure tests pass
- Let CI/CD catch other issues

---

## Summary: Top Violations to Avoid

1. **'I' prefix on interfaces**
2. **Relative imports (use # alias)**
3. **Single quotes (use double)**
4. **2 spaces (use 4)**
5. **Empty catch blocks**
6. **Nested conditionals (use early returns)**
7. **Magic numbers (use constants)**
8. **Mutable exports (use const)**
9. **More than 3 parameters (use object)**
10. **Repeating code 3+ times (extract)**

---

## How to Use This Document

**In Code Review:**
- Check PRs against this list
- Block merge if violations exist
- Point to specific sections when rejecting

**In Development:**
- Reference before committing
- Use as checklist for self-review
- Configure ESLint to catch these automatically

**When Learning:**
- Understand the "why" behind each rule
- See examples of correct patterns
- Reference related documents for more context

---

## Related Documents

- `100-typescript-patterns.md` - Correct TypeScript patterns
- `110-rust-patterns.md` - Correct Rust patterns
- `310-configuration.md` - ESLint/Prettier config that enforces these
- `020-decision-framework.md` - When to relax rules (rarely!)