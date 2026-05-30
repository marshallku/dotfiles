---
name: extract
description: Slash-command style URL-to-DESIGN.md extraction. Use when the user types /extract, asks to extract a DESIGN.md from a public HTTPS website URL, or asks for a design system, design blueprint, brand tokens, visual style, UI inspiration, or agent-ready design spec from a URL. Handles prompts like "/extract https://example.com", "Extract a DESIGN.md from https://...", "Make a design system document from this URL", and "이 링크 디자인 따서 DESIGN.md 만들어줘."
---

# Extract

Create a grounded `DESIGN.md` from a public website. Extract observable design patterns; do not clone the site as runnable code or claim official brand guidelines.

## Command Behavior

When the user types `/extract <url>`, treat it as a request to run this workflow immediately.

If the user types only `/extract`, ask for the public HTTPS URL and do not start extraction until they provide it.

Default output:

- evidence bundle: `.blueprint-extractor/<slug>/`
- final document: `DESIGN.md` in the user's current project unless they ask for another path

## Workflow

1. Validate the target URL.
2. Create an evidence folder at `.blueprint-extractor/<slug>/` in the user's project.
3. Gather evidence from public page data:
   - HTML title and metadata
   - linked and inline CSS
   - computed styles from representative elements
   - desktop screenshot at `1440x900` when browser tooling is available
   - mobile screenshot at `390x844` when browser tooling is available
4. Extract concrete tokens only from fetched CSS, computed styles, or recorded screenshots.
5. Write `blueprint.json` and `sources.json` before writing final prose.
6. Synthesize `DESIGN.md` using the exact 9-section contract in `references/DESIGN_TEMPLATE.md`.
7. Run a self-review pass before finalizing:
   - improve implementation usefulness with observed component recipes;
   - improve qualitative theme language when it is supported by screenshots;
   - separate extracted evidence from screenshot-inferred behavior and implementation guidance;
   - remove broad product claims that are not visible or present in extracted CSS;
   - preserve the target project's domain, information architecture, and core workflows; transfer visual language only;
   - abstract source-domain components before reuse, such as "playlist" to "collection list" or "album art" to "visual thumbnail";
   - keep unsupported examples out of `DESIGN.md` unless marked as qualitative or inferred.
8. Validate the final Markdown against the template and evidence.
9. Report the output path and any confidence warnings in the final response.

## URL Safety

Reject the request with a short explanation when the URL is unsafe or out of scope:

- not `https://`
- localhost, loopback, private IP, link-local, or private hostname
- auth-gated or paywalled content
- non-HTML response
- unreachable, empty, or redirecting too many times
- request to bypass login, scrape private dashboards, extract Figma, or clone runnable code

Do not follow forms, login flows, checkout flows, destructive actions, or user-specific pages.

## Extraction

If `scripts/extract-blueprint.mjs` exists and dependencies are available, run it first and use its artifacts as the source of truth. If it is unavailable, use available browser, HTTP, and filesystem tools to gather equivalent evidence manually.

Prefer deterministic evidence over visual guessing:

- Colors must come from CSS, computed styles, SVG attributes, or sampled screenshots.
- Font families must come from CSS, computed styles, or `@font-face`.
- Breakpoints must come from media queries or be explicitly marked as inferred from screenshots.
- Spacing, radius, shadows, borders, and motion must cite CSS or computed styles.
- If only screenshots are available, keep observations qualitative and avoid invented numeric tokens.

Read `references/EXTRACTION_SCHEMA.md` before creating or editing `blueprint.json` and `sources.json`.
Read `references/FAILURE_MODES.md` when extraction is partial or blocked.
Read `references/QUALITY_CHECKLIST.md` before treating a generated `DESIGN.md` as a good example or release-quality output.

## Synthesis Rules

Use the user's requested language. If no language is requested, write `DESIGN.md` in English.

The final `DESIGN.md` must contain exactly these H2 sections, in this order:

1. `1. Visual Theme & Atmosphere`
2. `2. Color Palette & Roles`
3. `3. Typography Rules`
4. `4. Component Stylings`
5. `5. Layout Principles`
6. `6. Depth & Elevation`
7. `7. Do's and Don'ts`
8. `8. Responsive Behavior`
9. `9. Agent Prompt Guide`

Do not add a Sources, Confidence, or Appendix section to `DESIGN.md`. Put confidence warnings in the final assistant response or in the evidence bundle.

Each concrete token in `DESIGN.md` must be traceable to `blueprint.json`. Mark uncertain findings as qualitative observations instead of exact values.

Do not make the final document a dry token dump. Convert evidence into reusable design guidance:

- Name the site archetype only when it is visible from the captured page, such as "dashboard shell", "editorial landing page", "commerce catalog", "media player", or "docs site".
- Treat famous brands conservatively: do not import well-known product patterns, brand lore, or official-system claims unless the captured page, CSS, or computed samples support them.
- Preserve the target app's domain model, information structure, and user workflows. The source site provides visual language, not permission to convert the target project into the source site's product category.
- Separate transferable design traits from non-transferable source-domain objects. Transfer color, typography, spacing, density, shape, surface layering, and interaction feel; do not transfer domain objects such as tracks, playlists, carts, docs pages, dashboards, or checkout flows unless the user explicitly asks for that product structure.
- When a source component is useful, phrase it as a domain-neutral pattern: "collection/navigation sidebar" instead of "playlist sidebar", "repeated content item" instead of "track row", "visual thumbnail or accent block" instead of "album art".
- Preserve the distinction between observed tokens, screenshot-inferred layout behavior, and implementation guidance in the prose.
- Turn observed recurring components into compact recipes: purpose, surface, typography, spacing, radius, border/shadow, interaction.
- Prefer patterns that generalize across the page over one-off decorative values.
- Distinguish extracted breakpoints from implementation-convenience breakpoints.
- Use `7. Do's and Don'ts` for concise constraints that prevent likely misreadings, including overusing accent colors, adding unsupported components, importing the source site's domain model, or changing the target project's product category.
- Make `9. Agent Prompt Guide` practical: quick color reference, example component prompts, and iteration guidance when evidence supports them.
- Keep the guidance inspired-by and implementation-ready without instructing an agent to clone the target site.

## Validation

Before finishing:

- Confirm `DESIGN.md` exists at the intended output path.
- Confirm the H2 section names and order match `references/DESIGN_TEMPLATE.md`.
- Confirm each hex color, font family, breakpoint, radius, shadow, and spacing value appears in `blueprint.json` or is explicitly marked as inferred/qualitative.
- Confirm the output satisfies `references/QUALITY_CHECKLIST.md` when creating an example or release candidate.
- If validation fails, fix the evidence or downgrade unsupported values before presenting the result.
