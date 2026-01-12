# 130: Common Patterns and Idioms

**Category:** CODE & DESIGN (100-199)
**Last Updated:** 2025-12-04

---

## Purpose

Patterns repeated across all projects - common idioms and utilities.

---

## XI. COMMON PATTERNS AND IDIOMS

### Repeated Patterns Across All Projects

#### 1. **The "to" Utility** (Error Handling)
```typescript
// ✅ Present in multiple projects - use this pattern
export default function to<T, E = Error>(
    promise: Promise<T>
): Promise<[E, null] | [null, T]> {
    return promise
        .then<[null, T]>((data: T) => [null, data])
        .catch<[E, null]>((error) => {
            if (error instanceof Error) {
                return [error as E, null];
            }
            return [{ message: "알 수 없는 오류가 발생했습니다" } as E, null];
        });
}

// Usage:
const [error, data] = await to(fetchData());
if (error) {
    handleError(error);
    return;
}
// use data safely
```

#### 2. **Path Alias with # Prefix**
```typescript
// ✅ ALWAYS use # for internal imports
import { helper } from "#utils";
import { type User } from "#types";
import { API_URL } from "#constants";

// ❌ NEVER use relative imports for non-adjacent files
import { helper } from "../../../utils/helper"; // ❌
```

#### 3. **Barrel Exports**
```typescript
// utils/index.ts
export * from "./lib/array";
export * from "./lib/string";
export * from "./lib/date";

// types/index.ts
export * from "./lib/user";
export * from "./lib/post";
```

#### 4. **Environment Configuration with Defaults**
```typescript
// ✅ Pattern used consistently
export class Config {
    public readonly port: number;
    public readonly host: string;

    constructor() {
        this.port = Number(process.env.PORT) || 3000;
        this.host = process.env.HOST || "localhost";
    }
}
```

#### 5. **Early Return Pattern**
```typescript
// ✅ Use extensively for guard clauses
function process(data: Data | null) {
    // Guard clauses first
    if (!data) return;
    if (!data.isValid) return;
    if (data.isProcessed) return;

    // Main logic only after all guards
    performProcessing(data);
}
```

#### 6. **Passive Event Listeners**
```typescript
// ✅ ALWAYS specify { passive: true } for scroll/touch events
element.addEventListener("scroll", handler, { passive: true });
element.addEventListener("touchmove", handler, { passive: true });

// ✅ Use { once: true } for one-time events
button.addEventListener("click", handler, { once: true });
```

#### 7. **Deterministic Randomness** (Rust projects)
```rust
// ✅ Pattern for reproducible layouts
pub fn generate_coordinate<T: Hash>(key: T, seed_base: u64) -> (f64, f64) {
    let mut hasher = DefaultHasher::new();
    key.hash(&mut hasher);
    let seed = hasher.finish() ^ seed_base;
    let mut rng = ChaCha8Rng::seed_from_u64(seed);

    let x = rng.gen_range(x_min..x_max);
    let y = rng.gen_range(y_min..y_max);

    (x, y)
}
```

---
