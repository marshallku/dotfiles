# Guide

Always follow this document, and act like you are a same person as this document.

---

## 🎯 How to Use This Index

**For AI Systems:**

1. **Always read this INDEX first** to understand the structure
2. **Read only the files you need** for the current task
3. **Don't read all files** - it wastes tokens
4. **Use the "When to Read" guide** below

**For Humans:**

- This is a navigation guide to the developer profile
- Each file is focused on a specific topic
- Files contain complete, unsummarized content from the original analysis

---

## 📁 File Structure

```
profiles/
├── 001-099: MINDSET
├── 100-199: CODE & DESIGN
├── 200-299: QUALITY & PERFORMANCE
├── 300-399: INFRASTRUCTURE
└── 900-999: REFERENCE
```

---

## 001-099: MINDSET

**Purpose:** Understand the developer's personality, values, and decision-making approach

### 001-who-am-i.md

**What:** Personal background, expertise, interests, life context
**When to Read:**

- First time working with this developer
- Need context about technical background
- Understanding work style preferences

### 010-personality-traits.md

**What:** 10 core personality traits that drive decisions
**When to Read:**

- Making decisions in ambiguous situations
- Need to predict how developer would choose
- Understanding "why" behind patterns
- **Most Important:** Contains "The Rule of Three" - universal principle

### 020-decision-framework.md

**What:** Step-by-step framework for technical decisions
**When to Read:**

- Facing a choice not explicitly documented
- Need to evaluate multiple options
- Understanding priority when principles conflict
- Includes real Q&A scenarios (tech adoption, refactoring, etc.)

---

## 100-199: CODE & DESIGN

**Purpose:** Language-specific patterns, architecture, and code organization

### 100-typescript-patterns.md

**What:** Complete TypeScript/JavaScript style guide
**When to Read:**

- Writing TypeScript/JavaScript code
- Need naming conventions
- Function structure patterns
- Type usage patterns
- Error handling in TS
- React/Next.js patterns

**Includes:**

- Naming conventions (camelCase, PascalCase, UPPER_CASE)
- Function structure (arrow functions, early returns)
- Type patterns (generics, utility types, type predicates)
- Component patterns (React/Next.js)
- Import organization
- Event handling

### 110-rust-patterns.md

**What:** Complete Rust style guide
**When to Read:**

- Writing Rust code
- Need Rust-specific patterns
- Error handling in Rust
- Async patterns

**Includes:**

- Naming conventions (snake_case, PascalCase)
- Result/Option patterns
- Trait usage
- Async/await patterns
- Pattern matching

### 120-architecture.md

**What:** File structure, module organization, layered architecture
**When to Read:**

- Starting new project
- Organizing code structure
- Deciding module boundaries
- Understanding layered architecture

**Includes:**

- Directory organization
- Module boundaries (Rule of Three applies)
- Barrel exports
- Path aliases (# prefix)
- Layered architecture (controllers → services → utils)
- Monorepo vs polyrepo decisions

### 130-common-patterns.md

**What:** Patterns repeated across all projects
**When to Read:**

- Need common idioms and utilities
- Looking for established patterns

**Includes:**

- The "to" utility (error handling)
- Path aliases with # prefix
- Barrel exports
- Environment config with defaults
- Early return pattern
- Passive event listeners

---

## 200-299: QUALITY & PERFORMANCE

**Purpose:** Testing strategies, performance optimization, error handling

### 200-testing.md

**What:** Testing philosophy, strategies, and patterns
**When to Read:**

- Writing tests
- Deciding test coverage
- Understanding testing investment

**Includes:**

- Testing philosophy (fast fail, not coverage %)
- Test structure (Vitest/Jest)
- What to test vs skip
- Testing by project type

### 210-performance.md

**What:** Performance optimization strategies
**When to Read:**

- Optimizing code
- Making performance decisions
- Understanding caching strategies

**Includes:**

- When to optimize (upfront vs measured)
- Caching strategies
- Cache TTL rules
- Streaming responses
- Lazy loading
- Pagination

### 220-error-handling.md

**What:** Error handling philosophy and patterns
**When to Read:**

- Handling errors
- Deciding custom errors vs generic
- Recovery vs fail-fast decisions

**Includes:**

- Custom error classes (when to use)
- Recovery vs fail-fast philosophy
- Go-style tuple destructuring
- Error handling by language

---

## 300-399: INFRASTRUCTURE

**Purpose:** DevOps, CI/CD, configuration, deployment

### 300-devops-cicd.md

**What:** CI/CD pipeline patterns, deployment strategies
**When to Read:**

- Setting up CI/CD
- Deploying applications
- GitHub Actions workflows

**Includes:**

- Standard CI/CD pipeline
- Quality gates
- Docker patterns
- Deployment automation

### 310-configuration.md

**What:** Tool configurations (ESLint, Prettier, TypeScript, etc.)
**When to Read:**

- Setting up new project
- Configuring tools
- Understanding tool choices

**Includes:**

- ESLint config (flat config format)
- Prettier config (120 chars, 4 spaces, double quotes)
- TypeScript config
- Package.json standards
- Why specific settings chosen

---

## 900-999: REFERENCE

**Purpose:** Quick reference, cheat sheets, anti-patterns

### 900-quick-reference.md

**What:** Cheat sheet for quick lookup
**When to Read:**

- Need quick reminder
- Checking naming conventions
- Common code patterns

**Includes:**

- Naming quick reference table
- Common code patterns
- ESLint/Prettier settings
- One-line reminders

### 910-anti-patterns.md

**What:** Things to NEVER do
**When to Read:**

- Reviewing code
- Checking for violations
- Understanding red flags

**Includes:**

- Never prefix interfaces with 'I'
- Never use relative imports beyond parent
- Never use single quotes
- Never use 2-space indentation
- And more...

### 920-project-setup.md

**What:** Checklist for starting new projects
**When to Read:**

- Starting new project
- Setting up repository
- Ensuring all configs present

**Includes:**

- Required config files
- Quality gates checklist
- Standard project structure

---

## 🤖 AI Usage Guide

### For Code Generation Tasks

**Step 1: Read This file**

**Step 2: Read relevant files based on task:**

| Task                        | Files to Read                                            |
| --------------------------- | -------------------------------------------------------- |
| Write TypeScript            | `100-typescript-patterns.md`                             |
| Write Rust                  | `110-rust-patterns.md`                                   |
| Make architectural decision | `120-architecture.md`, `020-decision-framework.md`       |
| Write tests                 | `200-testing.md`                                         |
| Optimize performance        | `210-performance.md`                                     |
| Handle errors               | `220-error-handling.md`                                  |
| Setup CI/CD                 | `300-devops-cicd.md`                                     |
| Configure tools             | `310-configuration.md`                                   |
| Quick lookup                | `900-quick-reference.md`                                 |
| Check violations            | `910-anti-patterns.md`                                   |
| Start new project           | `920-project-setup.md`, `310-configuration.md`           |
| Ambiguous decision          | `020-decision-framework.md`, `010-personality-traits.md` |

**Step 3: Apply patterns exactly as documented**

**Step 4: When uncertain, use decision framework**

---

## 🔑 Core Principles (Read These First)

If you can only read a few things, read these:

1. **The Rule of Three** (in `010-personality-traits.md`)
   - 3 repetitions → extract
   - 3+ parameters → object
   - 3+ concerns → split
   - **Universal principle**

2. **Decision Framework** (in `020-decision-framework.md`)
   - Step-by-step evaluation
   - Priority matrix
   - Language-specific defaults

3. **Quality-First Shipper** (in `010-personality-traits.md`)
   - Build it right from the start
   - Compromise only for extreme deadlines

4. **Pragmatist Over Purist** (in `010-personality-traits.md`)
   - Working solution > theoretical perfection
   - Relax rules when practical

---

## 📞 How to Maintain

**When to Update:**

- New patterns emerge from projects
- Preferences evolve
- Technology stack changes
- Core principles change

**How to Update:**

1. Update relevant file(s)
2. Update "Last Updated" date in that file
3. Add note in version history if significant

---

## ⚡ Emergency Quick Reference

**Can't decide?** → Read `020-decision-framework.md`

**Need code pattern?** → Read `100-typescript-patterns.md` or `110-rust-patterns.md`

**Check if something is wrong?** → Read `910-anti-patterns.md`

**Starting new project?** → Read `920-project-setup.md`

**Need to understand "why"?** → Read `010-personality-traits.md`

---

**Remember:** This is a living document. Patterns evolve. When in doubt, refer to the decision framework and core principles.

