# 220: Error Handling Patterns

**Category:** QUALITY & PERFORMANCE (200-299)
**Last Updated:** 2025-12-04

---

## Purpose

Error handling philosophy, custom errors vs generic, recovery vs fail-fast.

---

## TypeScript Error Handling

See extracted patterns from 100-typescript-patterns.md and decision framework (020-decision-framework.md Q3, Q4).

### Go-Style Tuple Destructuring

```typescript
const [error, data] = await to(asyncOperation());
if (error) {
    console.error(error);
    return;
}
// use data safely
```

### Early Returns

```typescript
if (!isValid) {
    return;
}
```

### Custom Error Classes

**Create when:** Different errors need different handling
**Reality:** Not very common - most cases use standard Error

```typescript
// Only when truly needed
class ValidationError extends Error { }
class NetworkError extends Error { }

// Default
throw new Error("Descriptive message");
```

### Recovery vs Fail-Fast

**Default strategy:** Retry/recover (optimistic approach)

**Fail-fast only for:**
- System-critical issues
- Data integrity violations

**Ignore/optimistic handling for:**
- Logging (non-essential operations)
- Errors very unlikely in production

**This explains the `.ok()` pattern in Rust code** - non-critical operations can fail without stopping execution.

## Rust Error Handling

```rust
// Result types for fallible operations
pub async fn fetch_data(url: &str) -> Result<Data, Error> {
    let response = reqwest::get(url).await?;
    let data = response.json().await?;
    Ok(data)
}

// Pragmatic .ok() for non-critical errors
fs::create_dir_all(path).ok();
fs::write(path, data).ok();
```

---

See also:
- `100-typescript-patterns.md` - TypeScript error patterns
- `110-rust-patterns.md` - Rust error patterns
- `020-decision-framework.md` - Q3, Q4 for decisions