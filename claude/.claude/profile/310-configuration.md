# 310: Tool Configuration

**Category:** INFRASTRUCTURE (300-399)
**Last Updated:** 2025-12-04

---

## Purpose

ESLint, Prettier, TypeScript, and other tool configurations with rationale.

---

## VII. CONFIGURATION PREFERENCES

### TypeScript Configuration
```json
{
    "compilerOptions": {
        "target": "ES2021",
        "module": "ESNext",
        "lib": ["ES2021", "DOM"],
        "jsx": "react-jsx",
        "strict": true,
        "esModuleInterop": true,
        "skipLibCheck": true,
        "forceConsistentCasingInFileNames": true,
        "resolveJsonModule": true,
        "allowSyntheticDefaultImports": true,
        "paths": {
            "#*": ["./src/*"]
        }
    }
}
```

**VARIATIONS BY PROJECT TYPE**:
- Libraries: `declaration: true` (generate .d.ts files)
- Applications: May relax `strictNullChecks` for pragmatism
- Always: `strict: true` as starting point

### ESLint Configuration
```javascript
export default [
    {
        rules: {
            // Naming conventions (enforced strictly)
            "@typescript-eslint/naming-convention": [
                "error",
                { selector: "variable", format: ["camelCase", "PascalCase", "UPPER_CASE"] },
                { selector: "function", format: ["camelCase", "PascalCase"] },
                { selector: "typeLike", format: ["PascalCase"] },
            ],

            // Import ordering (enforced)
            "import/order": ["error", {
                "groups": ["builtin", "external", "internal"],
                "newlines-between": "always",
                "alphabetize": { "order": "asc" }
            }],

            // Console logs (warnings, not errors)
            "no-console": ["warn", { allow: ["warn", "error"] }],

            // Unused vars (must prefix with _)
            "@typescript-eslint/no-unused-vars": ["error", {
                "argsIgnorePattern": "^_",
                "varsIgnorePattern": "^_"
            }],

            // Relaxed rules (pragmatic choices)
            "@typescript-eslint/explicit-function-return-type": "off",
            "@typescript-eslint/no-explicit-any": "warn", // warn, not error
        }
    }
];
```

### Package Manager: pnpm
- **Always use pnpm**, not npm or yarn
- Workspaces for monorepos
- Exact versions in package.json (no ^ or ~)

---
