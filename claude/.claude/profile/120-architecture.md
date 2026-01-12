# 120: Architecture Patterns

**Category:** CODE & DESIGN (100-199)
**Last Updated:** 2025-12-04

---

## Purpose

File structure, module organization, layered architecture, and monorepo decisions.

---

## III. ARCHITECTURAL PATTERNS

### File Structure Philosophy

#### Directory Organization (Universal Across Projects)
```
project/
├── src/
│   ├── components/        # UI components (if applicable)
│   ├── controllers/       # Request handlers (backend)
│   ├── services/          # Business logic
│   ├── utils/             # Shared utilities
│   │   ├── lib/           # Actual implementations
│   │   └── index.ts       # Barrel export
│   ├── types/             # Type definitions
│   │   ├── lib/           # Individual type files
│   │   └── index.ts       # Barrel export
│   ├── constants/         # Application constants
│   ├── api/               # External API interactions
│   └── env/               # Environment configuration
├── __tests__/             # Tests (co-located or separate)
├── package.json           # Dependencies
└── README.md              # Documentation
```

**RULES**:
1. Each directory has `index.ts` (TypeScript) or `mod.rs` (Rust) for barrel exports
2. Actual implementations in `lib/` subdirectory
3. Tests in `__tests__/` directories (co-located with source)
4. Configuration files at root level
5. One main concept per file (single responsibility)

#### Module Organization
```typescript
// ✅ Barrel exports (index.ts)
export * from './lib/array';
export * from './lib/string';
export * from './lib/date';

// ✅ Path aliases with # prefix
import { helper } from '#utils';
import { API_URL } from '#constants';
import { type User } from '#types';

// ❌ NEVER use relative imports beyond parent
import { helper } from '../../../utils'; // ❌
```

### Layered Architecture

#### Layer Responsibilities (Always Enforce)
```
┌─────────────────────────────────────┐
│  Controllers / Handlers             │  ← HTTP/WebSocket entry points
│  - Request validation                │  ← Parse and validate input
│  - Response formatting               │  ← Format output
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│  Services                           │  ← Business logic
│  - Core operations                  │  ← Domain operations
│  - Orchestration                    │  ← Coordinate multiple operations
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│  Utils / Helpers                    │  ← Pure functions
│  - Data transformation              │  ← Stateless operations
│  - Common utilities                 │  ← Reusable functions
└─────────────────────────────────────┘
```

**RULES**:
- Controllers NEVER contain business logic
- Services NEVER directly handle HTTP concerns
- Utils MUST be pure functions (no side effects when possible)
- Data flows downward, never upward

---
