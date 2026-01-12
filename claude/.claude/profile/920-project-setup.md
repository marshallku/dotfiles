# 920: Project Setup Checklist

**Category:** REFERENCE (900-999)
**Last Updated:** 2025-12-04

---

## Purpose

Complete checklist for starting new projects. Ensures all required configurations, quality gates, and standards are in place from day one.

---

## Required Configuration Files

### 1. package.json (TypeScript projects)

```json
{
    "name": "@scope/project-name",
    "version": "0.1.0",
    "packageManager": "pnpm@9.12.2",
    "scripts": {
        "dev": "next dev",
        "build": "next build",
        "test": "vitest",
        "lint": "eslint .",
        "format": "prettier --write .",
        "format:check": "prettier --check ."
    }
}
```

**Key points:**
- Use scoped package name (`@scope/project-name`)
- Specify `packageManager` for consistency
- Include all standard scripts

### 2. tsconfig.json

```json
{
    "extends": "@marshallku/typescript-config/base.json",
    "compilerOptions": {
        "baseUrl": ".",
        "paths": {
            "#*": ["./src/*"]
        }
    },
    "include": ["src/**/*"],
    "exclude": ["node_modules", "dist"]
}
```

**Key points:**
- Extend shared config if available
- Always set up path aliases with `#` prefix
- Include/exclude patterns

### 3. .prettierrc

```json
{
    "extends": "@marshallku/prettier-config"
}
```

Or full config:

```json
{
    "printWidth": 120,
    "tabWidth": 4,
    "useTabs": false,
    "semi": true,
    "singleQuote": false,
    "trailingComma": "all",
    "endOfLine": "auto"
}
```

### 4. eslint.config.js

```javascript
import baseConfig from "@marshallku/eslint-config";

export default [
    ...baseConfig,
    // Project-specific overrides
];
```

**Note:** Use flat config format (ESLint 9+)

### 5. .github/workflows/ci.yml

```yaml
name: CI/CD

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v2
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: "pnpm"

      - name: Install dependencies
        run: pnpm install

      - name: Spell check
        run: pnpm cspell

      - name: Lint
        run: pnpm lint

      - name: Format check
        run: pnpm format:check

  test:
    runs-on: ubuntu-latest
    steps:
      - name: Run tests
        run: pnpm test

      - name: Coverage
        run: pnpm coverage

  build:
    needs: [quality, test]
    runs-on: ubuntu-latest
    steps:
      - name: Build
        run: pnpm build
```

### 6. README.md

Structure:

```markdown
# Project Name

[![CI Status](badge)](link)
[![Coverage](badge)](link)

## Description

[What and why]

## Installation

[Steps]

## Usage

[Examples]

## Development

[Setup for contributors]
```

### 7. Dockerfile (if applicable)

```dockerfile
# Build stage
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN pnpm install
COPY . .
RUN pnpm build

# Production stage
FROM node:20-alpine AS runner
WORKDIR /app
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/public ./public
EXPOSE 3000
CMD ["node", "server.js"]
```

### 8. .gitignore

```
# Dependencies
node_modules/

# Build output
dist/
.next/
out/

# Environment
.env*.local
.env

# Testing
coverage/

# Logs
*.log
npm-debug.log*
pnpm-debug.log*

# OS
.DS_Store
Thumbs.db

# Editor
.vscode/
.idea/
```

### 9. cspell.json (Spell Checking)

```json
{
    "version": "0.2",
    "language": "en",
    "words": [
        "marshallku",
        "pnpm"
    ],
    "ignorePaths": [
        "node_modules",
        "dist",
        "*.lock",
        "pnpm-lock.yaml"
    ]
}
```

---

## Quality Gates Checklist

Before merging to main, ensure:

- [ ] **Spell check passes** (`pnpm cspell`)
- [ ] **ESLint passes** (no errors, warnings acceptable)
- [ ] **Prettier check passes** (`pnpm format:check`)
- [ ] **All tests pass** (`pnpm test`)
- [ ] **Build succeeds** (`pnpm build`)
- [ ] **Coverage above threshold** (usually 80%)
- [ ] **No console.log** (only warn/error allowed)
- [ ] **Documentation updated** (if public API changed)

---

## Directory Structure Template

### Web Application (Next.js)

```
project/
├── .github/
│   └── workflows/
│       └── ci.yml
├── public/
│   └── assets/
├── src/
│   ├── app/                 # Next.js App Router
│   ├── components/
│   │   ├── Button/
│   │   │   ├── index.tsx
│   │   │   ├── index.module.scss
│   │   │   └── index.test.tsx
│   │   └── index.ts         # Barrel export
│   ├── utils/
│   │   ├── lib/
│   │   │   ├── array.ts
│   │   │   └── string.ts
│   │   └── index.ts
│   ├── types/
│   │   ├── lib/
│   │   └── index.ts
│   ├── constants/
│   │   └── index.ts
│   └── __tests__/
├── .eslintrc.json
├── .prettierrc
├── .gitignore
├── tsconfig.json
├── package.json
├── pnpm-lock.yaml
├── README.md
└── Dockerfile
```

### Library (npm package)

```
library/
├── src/
│   ├── index.ts             # Main entry
│   ├── lib/
│   │   ├── feature1.ts
│   │   └── feature2.ts
│   ├── types/
│   │   └── index.ts
│   └── __tests__/
├── dist/                    # Build output
│   ├── index.js             # CJS
│   ├── index.mjs            # ESM
│   └── index.d.ts           # Types
├── tsconfig.json
├── rollup.config.js         # or tsup.config.ts
├── package.json
└── README.md
```

### Backend Service (NestJS)

```
api/
├── src/
│   ├── main.ts
│   ├── app.module.ts
│   ├── auth/
│   │   ├── auth.module.ts
│   │   ├── auth.controller.ts
│   │   ├── auth.service.ts
│   │   └── auth.guard.ts
│   ├── users/
│   ├── constants/
│   └── utils/
├── test/
│   └── app.e2e-spec.ts
├── nest-cli.json
├── tsconfig.json
├── package.json
└── Dockerfile
```

---

## Bilingual Setup (Korean + English)

**Code & Comments:** English

```typescript
// ✅ Code in English
const userName = getUserName();
function fetchPosts() { }

// ✅ Comments in English
// TODO: Refactor after API update
```

**User-Facing Messages:** Korean

```typescript
// ✅ User messages in Korean
throw new Error("알 수 없는 오류가 발생했습니다");
toast("댓글이 등록되었습니다");
const placeholder = "댓글을 입력해주세요";
```

---

## Project-Type Specific Patterns

### Web Applications (Next.js, React)

```typescript
// ✅ Server components by default
export default async function Page() {
    const data = await fetchData();
    return <View data={data} />;
}

// ✅ Client components explicitly marked
"use client";
export default function InteractiveComponent() {
    const [state, setState] = useState();
    return <div onClick={() => setState(next)} />;
}

// ✅ Static generation enforced
export const dynamic = "error";
```

### Libraries (npm packages)

```typescript
// ✅ Named exports for libraries
export function helper1() { }
export function helper2() { }
export { default as Main } from "./Main";

// ✅ Type definitions included
export type { HelperOptions } from "./types";

// ✅ CJS + ESM support via dual build
```

### Backend Services

**NestJS:**
```typescript
// Global guards with decorator opt-out
@Injectable()
export class AuthGuard implements CanActivate {
    canActivate(context: ExecutionContext): boolean {
        const isPublic = this.reflector.get(IS_PUBLIC_KEY, context.getHandler());
        if (isPublic) return true;
        // ... auth logic
    }
}

@Public() // Opt-out decorator
@Get()
publicEndpoint() { }
```

**Axum (Rust):**
```rust
pub async fn handler(
    State(state): State<AppState>,
    Path(params): Path<Params>
) -> Result<Response, StatusCode> {
    // handler logic
}
```

---

## Initial Commit Checklist

Before first commit:

- [ ] All config files created
- [ ] Dependencies installed (`pnpm install`)
- [ ] Linter passes (`pnpm lint`)
- [ ] Formatter passes (`pnpm format:check`)
- [ ] Project builds (`pnpm build`)
- [ ] Basic test exists and passes
- [ ] README has project description
- [ ] .gitignore configured
- [ ] CI/CD workflow added

---

## Post-Setup Verification

Run these commands to verify setup:

```bash
# Install dependencies
pnpm install

# Check formatting
pnpm format:check

# Run linter
pnpm lint

# Run tests
pnpm test

# Build project
pnpm build

# Spell check
pnpm cspell
```

All should pass before proceeding with development.

---

## Related Documents

- `310-configuration.md` - Detailed config explanations
- `300-devops-cicd.md` - Full CI/CD patterns
- `100-typescript-patterns.md` - TypeScript coding patterns
- `120-architecture.md` - Project structure guidelines