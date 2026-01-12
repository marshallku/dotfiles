# 020: Decision-Making Framework

**Category:** MINDSET (001-099)
**Last Updated:** 2025-12-04

---

## Overview

This document provides a systematic framework for making technical decisions in ambiguous situations. Use this when facing choices not explicitly covered in other documents.

---

## Core Decision Process

### Step 1: Evaluate Against Core Principles

**Ask these questions in order:**

#### 1. Clarity: Will this make the code easier or harder to understand?
- If harder → reject or find alternative
- If easier → continue evaluation

#### 2. Performance: Does this impact performance?
- If negative impact → can we optimize it?
- If positive impact → strong candidate
- If neutral → continue evaluation

#### 3. Maintainability: Will this be easy to change later?
- If creates coupling → find alternative
- If decoupled → continue evaluation

#### 4. Pragmatism: What's the cost/benefit ratio?
- If high cost, low benefit → reject
- If low cost, high benefit → accept
- If high cost, high benefit → evaluate tradeoffs

---

### Step 2: Language/Framework-Specific Defaults

#### TypeScript/JavaScript
- **Default:** Modern ES features, TypeScript strict mode
- **Relax if:** TypeScript fights you on something that's definitely safe
- **Never relax:** Naming conventions, import organization, formatting

#### Rust
- **Default:** Idiomatic Rust, leverage type system
- **Relax if:** Borrow checker demands architectural compromise
- **Never relax:** Error handling, memory safety

#### Architecture
- **Default:** Layered architecture with clear boundaries
- **Relax if:** Tiny project (< 500 lines) where layers add overhead
- **Never relax:** Single responsibility principle

---

### Step 3: Check for Existing Patterns

**Before implementing something new:**
1. Search codebase for similar problems
2. Match existing pattern if found
3. Only create new pattern if truly unique situation

---

### Step 4: Optimize for Reading, Not Writing

**Remember:**
- Code is read 10x more than written
- Optimize for the reader (future you or team members)
- Explicit is better than implicit
- Boring is better than clever

---

## Specific Decision Scenarios

### New Technology Adoption

**Personal Projects:**
- Try if it solves a problem I've faced
- Experiment freely
- Use as laboratory for learning

**Production:**
- Wait for maturity before adoption
- **Evaluation factors:**
  - Community size
  - Stability/maturity
  - Improvement points
  - Risk vs benefit ratio

**Strategy:** Experiment personally → validate → adopt in production

**Case Study - Bun:**
- Early: Performance-focused marketing
- Later: Features added, performance degraded
- Result: Skeptical view
- **Lesson:** Be cautious of marketing hype, validate claims

---

### Technical Debt vs Shipping Fast

**Default Stance:** Build it right from the start

**Philosophy:** "Technical debt is expensive, better to invest upfront"

**Quality Priority:**
- Unless extreme deadline pressure
- Strong bias toward quality over speed

**Compromise Conditions:**
- **Only for:** Externally critical deadlines
- **Example:** 4-hour emergency feature
- **Frequency:** Rare, exceptional cases only

**Decision Rule:**
- If deadline is not externally critical → maintain quality
- If deadline is life-or-death → minimal viable quality, plan refactor

---

### Breaking Changes in Libraries/APIs

**Goal:** Maintain backward compatibility maximally

**Allow Breaking Changes When:**
- Critical performance issues
- Design limitations block new features
- Current design is fundamentally flawed

**Method:**
1. Major version bump (semantic versioning)
2. Sometimes add `@Deprecated` warnings first
3. Provide migration guide
4. Give users time to upgrade

**Balance:** Stability for users vs long-term maintainability

**Decision Rule:**
- Can it be done backward-compatibly? → Do that
- Is it critical for future? → Break with clear communication
- Is it just nicer? → Wait or find backward-compatible way

---

### Code Review Non-Negotiables

**Must Fix (Block Merge):**
- Excessive code repetition
- Performance problems
- Severely low code quality
- Obvious bugs or dead code

**Flexible On (Suggest, Don't Block):**
- Everything else
- Style preferences (if automated tools pass)
- Alternative approaches (if both work)

**Focus:** High-impact issues only, avoid bikeshedding

**Philosophy:** Code review for critical issues, automation for style

---

### Refactoring Triggers

**Refactor When:**
- Similar bugs recurring
- New features would degrade quality
- Convention changes or violations

**Frequency:** Quite frequently, quickly

**Rewrite When:**
- Code analysis becomes impossible
- **Process:**
  1. Understand current behavior
  2. Rewrite from scratch
  3. Verify behavior matches

**Philosophy:** Proactive refactoring - don't let code rot

**Decision Rule:**
- Can understand code? → Refactor incrementally
- Cannot understand code? → Understand behavior, then rewrite

---

### Dependency Management

**Personal Preference:** Implement yourself (for learning and control)

**Production Criteria:**

#### Use Library When:
- Solves our exact problem
- Well-maintained and stable
- Community support exists
- Security-critical (crypto, auth)

#### Fork/Modify When:
- Close match (70%+ overlap)
- Can be adjusted to our needs
- Active upstream for security updates

#### Implement When:
- < 70% match with existing solutions
- Library is hard to modify
- Very simple functionality
- Zero-dependency goal (like smooth-zoom)

**Example:** smooth-zoom is zero-dependency by choice, but production projects pragmatically use libraries

**Decision Framework:**
```
1. Does library solve exact problem?
   ├─ Yes → Use it
   └─ No → Continue

2. Can we modify it to fit?
   ├─ Yes, easily → Fork/modify
   └─ No or hard → Continue

3. Is it < 70% match OR hard to modify?
   ├─ Yes → Implement ourselves
   └─ No → Reconsider using library
```

---

### Documentation Investment

**Current Trend:** Documenting all applications extensively

**Prioritize Documentation For:**
- Collaborative projects
- Public libraries/APIs
- Complex systems
- Onboarding new team members

**Minimal Documentation For:**
- Solo projects
- Proof of concepts
- Self-explanatory code

**Shift:** Moving toward more documentation as projects mature and teams grow

**Decision Rule:**
- Working alone on PoC? → Minimal docs
- Team project or library? → Comprehensive docs
- When in doubt? → Document

---

### Experimentation Process

**Safe Experimentation Strategy:**

#### Process:
1. **Interesting?** → Try in side project
2. **Works well?** → Adopt in production
3. **Fails?** → Abandon or iterate in side project

**Personal projects are the laboratory**

**Never:**
- Experiment directly in production
- Try unproven tech in critical systems

**Always:**
- Validate in safe environment first
- Measure real-world impact before adopting

---

## Decision Priority Matrix

When multiple principles conflict, use this priority:

### Priority Order:
1. **Rule of Three** (Universal - highest priority)
2. **Safety/Security** (Non-negotiable)
3. **Quality-First Shipper** (Default stance)
4. **Performance-Aware** (Technical decisions)
5. **Pragmatist Over Purist** (Tie-breaker)

### Examples:

**Scenario:** Should I add a 4th parameter or refactor?
- Rule of Three says: Refactor to object
- **Decision:** Refactor (Rule #1 wins)

**Scenario:** Fast library with security issues vs slow but secure?
- Safety/Security says: Secure
- Performance-Aware says: Fast
- **Decision:** Secure library (Safety #2 wins over Performance #4)

**Scenario:** Perfect code but misses deadline vs working code on time?
- Quality-First says: Perfect code
- Pragmatist says: Working code
- **Decision:** Depends on deadline criticality
  - External critical deadline → Pragmatist wins
  - Internal deadline → Quality wins

---

## Quick Decision Checklist

For any technical decision:

- [ ] Does it pass the clarity test?
- [ ] Does it pass the performance test?
- [ ] Does it pass the maintainability test?
- [ ] Is the cost/benefit ratio favorable?
- [ ] Does it match existing patterns?
- [ ] Is it optimized for reading?
- [ ] Does it follow the Rule of Three?
- [ ] Would I accept this in code review?

**If all yes → Proceed**
**If any critical no → Reconsider**

---

## Remember

**The Goal:** Make decisions that future you will thank you for

**The Method:** Systematic evaluation, not gut feeling

**The Balance:** Pragmatism with principles, not dogma

**The Outcome:** Code that is clear, performant, maintainable, and ships