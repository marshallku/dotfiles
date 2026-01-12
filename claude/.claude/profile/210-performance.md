# 210: Performance Patterns

**Category:** QUALITY & PERFORMANCE (200-299)
**Last Updated:** 2025-12-04

---

## Purpose

Performance optimization strategies, caching, and when to optimize.

---

## VIII. PERFORMANCE PATTERNS

### Performance Philosophy

**Core Approach:**
- Naturally likes performance optimization
- Uses optimized loops: `for (i = 0, max = arr.length; i < max; ++i)`
- Prioritizes bundle size reduction
- Balance: Experience-driven upfront + data-driven reactive optimization

**When to Optimize:**
- **Upfront:** Simple to implement + known problem from experience (e.g., image lazy loading)
- **After measurement:** When monitoring shows actual issues
- **Never:** Premature optimization for hypothetical problems

**Cache TTL Strategy:**
- **Static files:** As long as possible (1 year)
- **Dynamic data:** Based on change frequency (frequent changes → short TTL, rare changes → long TTL)
- **Rule:** Cache lifetime inversely proportional to change frequency

### Optimization Strategies (Apply by Default)

#### 1. **Caching Strategy**
```typescript
// ✅ Check cache first
const cached = await cache.get(key);
if (cached) {
    return cached;
}

// Fetch and cache
const fresh = await fetchData();
await cache.set(key, fresh);
return fresh;
```

#### 2. **Streaming Responses** (When dealing with large files)
```rust
// ✅ PREFERRED: Stream instead of loading into memory
let file = tokio::fs::File::open(file_path).await?;
let stream = ReaderStream::new(file);
let body = Body::from_stream(stream);
```

#### 3. **Lazy Loading**
```typescript
// ✅ Process on demand, not upfront
const images = new Map(); // Don't process all images
function getImage(id: string) {
    if (!images.has(id)) {
        images.set(id, processImage(id)); // Process only when needed
    }
    return images.get(id);
}
```

#### 4. **Pagination/Limiting** (Always limit database queries)
```typescript
// ✅ Always use limits
const POSTS_PER_PAGE = 20;
const posts = await db.posts.find().limit(POSTS_PER_PAGE);

// ❌ NEVER fetch all
const posts = await db.posts.find(); // Could be millions!
```

#### 5. **Parallel Operations**
```typescript
// ✅ PREFERRED: Parallel when independent
const [users, posts, comments] = await Promise.all([
    fetchUsers(),
    fetchPosts(),
    fetchComments(),
]);

// ❌ AVOID: Sequential when parallel is possible
const users = await fetchUsers();
const posts = await fetchPosts();
const comments = await fetchComments();
```

---
