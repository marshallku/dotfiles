# 200: Testing Philosophy and Patterns

**Category:** QUALITY & PERFORMANCE (200-299)
**Last Updated:** 2025-12-04

---

## Purpose

Testing strategies, coverage goals, and when to invest in tests.

---

## VI. TESTING PHILOSOPHY

### Testing Strategy

#### Test Organization
```
src/
├── components/
│   ├── Button/
│   │   ├── index.tsx
│   │   └── index.test.tsx  ← Co-located
│   └── __tests__/          ← Or grouped
└── utils/
    ├── lib/
    │   └── array.ts
    └── __tests__/
        └── array/
            └── groupBy.test.ts
```

#### Test Structure (Vitest/Jest)
```typescript
import { describe, expect, it, beforeEach, afterEach } from 'vitest';

describe('ComponentName', () => {
    // Setup/teardown
    beforeEach(() => {
        // Setup
    });

    afterEach(() => {
        // Cleanup
    });

    // Grouped by functionality
    describe('Initialization', () => {
        it('should initialize with default values', () => {
            // Arrange
            const instance = create();

            // Act
            const result = instance.getValue();

            // Assert
            expect(result).toBe(expected);
        });
    });

    describe('Edge cases', () => {
        it('should handle null input gracefully', () => {
            // Test edge case
        });
    });
});
```

**RULES**:
- Test names start with "should"
- Arrange-Act-Assert pattern
- Group related tests in `describe` blocks
- Test edge cases explicitly
- Integration tests over unit tests (test behavior, not implementation)

---
