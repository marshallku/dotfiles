# 110: Rust Patterns

**Category:** CODE & DESIGN (100-199)
**Last Updated:** 2025-12-04

---

## Purpose

Complete Rust coding patterns for performance-critical backend services.

---

### Rust (Secondary Language for Performance-Critical Services)

#### Naming Conventions
```rust
// Variables and functions: snake_case
let user_name = get_user_name();
let file_path = PathBuf::from("path");
async fn process_request() { }

// Types and Structs: PascalCase
struct UserProfile { }
enum RequestStatus { }
trait Renderable { }

// Constants: SCREAMING_SNAKE_CASE
const MAX_CONNECTIONS: u32 = 100;
const DEFAULT_PORT: u16 = 8080;
```

#### Function Structure
```rust
// ✅ PREFERRED: Result types for fallible operations
pub async fn fetch_data(url: &str) -> Result<Data, Error> {
    let response = reqwest::get(url).await?;
    let data = response.json().await?;
    Ok(data)
}

// ✅ PREFERRED: Early returns for validation
pub fn process(input: &str) -> Option<String> {
    if input.is_empty() {
        return None;
    }
    Some(input.to_string())
}

// ✅ PRAGMATIC: .ok() for non-critical errors
fs::create_dir_all(path).ok(); // Ignore error if already exists
fs::write(path, data).ok(); // Best effort write
```

#### Pattern Matching
```rust
// ✅ PREFERRED: Exhaustive pattern matching
match result {
    Ok(data) => process(data),
    Err(error) => {
        error!("Failed: {:?}", error);
        return;
    }
}

// ✅ PREFERRED: if let for single pattern
if let Some(value) = optional {
    use_value(value);
}
```

#### Architecture Patterns
```rust
// ✅ Trait-based polymorphism
pub trait Renderable {
    fn render(&self) -> String;
}

// ✅ Type state pattern with enums
#[derive(Debug, Clone, Copy, Hash, Eq, PartialEq)]
pub enum Status {
    Pending,
    Processing,
    Complete,
}

// ✅ Dependency injection via function parameters
pub async fn handle_request(state: &AppState, request: Request) -> Response {
    // Use state
}
```

---

