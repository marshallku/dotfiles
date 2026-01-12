# 300: DevOps and CI/CD

**Category:** INFRASTRUCTURE (300-399)
**Last Updated:** 2025-12-04

---

## Purpose

CI/CD pipeline patterns, deployment strategies, Docker configuration.

---

## IX. DEPLOYMENT AND DEVOPS

### Docker Patterns

#### Multi-stage Build (Always Use)
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

### CI/CD Pipeline (GitHub Actions)

**Standard Workflow Structure**:
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
      - name: Coverage report
        run: pnpm coverage

  build:
    needs: [quality, test]
    runs-on: ubuntu-latest
    steps:
      - name: Build
        run: pnpm build
      - name: Build Docker image
        run: docker build -t app:latest .

  deploy:
    needs: build
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - name: Deploy
        run: ./deploy.sh
```

**ALWAYS INCLUDE**:
- Spell checking (cspell)
- Linting and formatting checks
- Test execution
- Code quality analysis (SonarQube)
- Build verification
- Automated deployment on main branch

---
