# 100: TypeScript/JavaScript Patterns

**Category:** CODE & DESIGN (100-199)
**Last Updated:** 2025-12-04

---

## Purpose

Complete TypeScript and JavaScript coding patterns, covering naming, functions, types, error handling, and React/Next.js patterns.

---

### TypeScript/JavaScript (Primary Language)

#### Naming Conventions
```typescript
// Variables and functions: camelCase
const userProfile = getUserProfile();
const isAuthenticated = checkAuth();
const postSlug = generateSlug(title);

// Components and Types: PascalCase
interface UserProfile { }
type Post = { };
function Button({ children }: ButtonProps) { }
class AuthService { }

// Constants: UPPER_CASE
const MAX_RETRY_COUNT = 3;
const DEFAULT_TIMEOUT = 5000;
const API_BASE_URL = "https://api.example.com";

// NEVER prefix interfaces with 'I' (IUserProfile ❌)
// NEVER use Hungarian notation (strName ❌)

// Unused variables: prefix with underscore
const [_error, data] = await to(promise);
```

#### Function Structure
```typescript
// ✅ PREFERRED: Arrow functions for most cases
const fetchUser = async (id: string) => {
    // Early returns for validation
    if (!id) {
        return null;
    }

    // Main logic
    const user = await api.get(`/users/${id}`);
    return user;
};

// ✅ PREFERRED: Default export for main component/function
export default function Component() { }

// ✅ PREFERRED: Named exports for utilities
export const helper1 = () => { };
export const helper2 = () => { };

// ✅ PARAMETER RULES:
// - 0-2 params: individual parameters
// - 3+ params: destructured object
function bad(a: string, b: number, c: boolean, d: object) { } // ❌
function good({ a, b, c, d }: Params) { } // ✅

// ✅ EARLY RETURNS (guard clauses)
function process(data: Data) {
    if (!data) return; // Early return
    if (data.invalid) return; // Early return

    // Main logic only after guards
    performProcessing(data);
}
```

#### Type Patterns
```typescript
// ✅ INLINE type imports (enforced by ESLint)
import { type User, type Post } from './types';

// ✅ Utility types heavily used
type PostWithoutContent = Omit<Post, 'content'>;
type PartialUser = Partial<User>;
type ReadonlyPost = Readonly<Post>;

// ✅ Generics for flexibility
function getValue<T>(array: T[], index: number): T | undefined {
    return array[index];
}

// ✅ Conditional types for complex scenarios
type Result<T extends boolean> = T extends true ? Success : Error;

// ✅ Type predicates for narrowing
function isString(value: unknown): value is string {
    return typeof value === 'string';
}

// ✅ Const enums for internal constants
const enum Direction {
    Up = "UP",
    Down = "DOWN",
}
```

#### Error Handling
```typescript
// ✅ PREFERRED: Go-style tuple destructuring
const [error, data] = await to(asyncOperation());
if (error) {
    console.error(error);
    return;
}
// use data

// ✅ PREFERRED: Early returns on error
if (!isValid) {
    return;
}

// ✅ Optional chaining and nullish coalescing
const value = obj?.nested?.property ?? defaultValue;

// ⚠️ ACCEPTABLE: try-catch only when necessary
try {
    await riskyOperation();
} catch (error) {
    // Handle specific error, not generic catch-all
}

// ❌ AVOID: Nested error handling
if (condition) {
    try {
        // nested logic ❌
    } catch {
        // nested error ❌
    }
}
```

#### Event Listeners
```typescript
// ✅ ALWAYS specify options for performance
element.addEventListener('click', handler, { passive: true });
element.addEventListener('scroll', handler, { passive: true, once: true });

// ✅ Cleanup with once: true when appropriate
button.addEventListener('click', handler, { once: true });
```
### Component Structure (React/TypeScript)

```typescript
// 1. "use client" directive (if needed)
"use client";

// 2. Imports (grouped as above)
import { useState } from "react";
import styles from "./index.module.scss";

// 3. Type definitions
interface ComponentProps {
    title: string;
    onClose?: () => void;
}

// 4. Constants
const cx = classNames(styles, "component");

// 5. Main component
export default function Component({ title, onClose }: ComponentProps) {
    // Hooks first
    const [state, setState] = useState();

    // Event handlers
    const handleClick = () => {
        // ...
    };

    // Early returns for conditionals
    if (!title) {
        return null;
    }

    // JSX
    return (
        <div className={cx()}>
            {/* content */}
        </div>
    );
}

// 6. DisplayName (for debugging)
Component.displayName = "Component";
```

### Class Names Pattern (BEM-inspired)

```typescript
// ✅ Custom classNames utility pattern
const cx = classNames(styles, "root");

// Usage:
cx()                    // → "root"
cx("__element")         // → "root__element"
cx("--modifier")        // → "root--modifier"
cx("", "--disabled")    // → "root root--disabled"
cx({ className: "external" }) // → "root external"
```

```scss
// Corresponding SCSS
.component {
    $self: &; // Store reference

    // Root styles
    display: flex;

    // Elements (double underscore)
    &__header {
        font-size: 1.5rem;
    }

    // Modifiers (double dash)
    &--disabled {
        opacity: 0.5;
    }

    // Nested with $self reference
    #{$self}:hover & {
        transform: scale(1.1);
    }
}
```

---
