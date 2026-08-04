---
name: scrollytelling
description: Build a public scrollytelling "How it works" page inside an app — a chapter-by-chapter narrative walkthrough of the product's end-to-end process with under-the-hood technical depth, scroll-driven animation, and a content-contract test. Use when the user asks for a "how it works" page, a scrollytelling walkthrough, a product narrative page, or something like sapphire's /how-it-works. The build doubles as an architecture review — report where the narrative outran the implementation.
---

# Scrollytelling "How it works" pages

A single-journey narrative page: the reader scrolls through the product's process
chapter by chapter, with enough technical detail that a software engineer or
solution architect could evaluate, extend, deploy, and operate the system.

Reference implementations: `~/code/projects/sapphire/frontend/src/pages/how-it-works/`
(TSX + Tailwind) and `~/code/projects/cellform/web/frontend/src/pages/how-it-works/`
(JSX + plain CSS tokens). Port the pattern to the host app's stack — never import
one app's styling idiom into another.

## Voice rules (non-negotiable)

- **Aspirational**: planned features are described as shipped, in present tense.
  Never "coming soon", "planned", "roadmap", "not yet", "in progress", "TODO".
  The test enforces this with a banned-words assertion.
- **Technical, not marketing**: name the real mechanisms (queue, snapshot chain,
  fuzzy matcher, PKCE, Parquet, import contracts). The reader is deciding whether
  to adopt or how to operate it — give them load-bearing nouns.
- **One journey**: chapters follow a single artifact through the system
  (a repository, a file, an order), then step back for cross-cutting chapters:
  trust boundary, architecture, security, deployment/operations.
- Each chapter = mono uppercase **eyebrow** (2–4 words) + **title** (verb-led or
  thesis-led) + **lede** (2–3 sentences, the chapter's whole argument) + a visual
  or card grid. If the AI/trust story exists, give it its own chapter — "AI
  proposes, deterministic checks decide" style theses land well.

## Process

1. **Study the host app first**: architecture docs, roadmap/plan (source of
   aspirational content), design tokens, routing, component-test conventions,
   whether framer-motion is installed (add it if not — it is the engine).
2. **Draft the chapter list** (10–14 chapters) before any code. Get the spine of
   the story right: journey chapters in pipeline order, then trust → architecture
   → deploy. Mine the roadmap for aspirational chapters and write them as real.
3. **Write the content-contract test first** (in the app's test idiom). It pins:
   - the H1 and every chapter heading (`getByRole('heading')`)
   - the key technical terms per chapter (case-insensitive body-text contains)
   - links (CTA hrefs)
   - the banned-words regex:
     `/coming soon|not yet|to be built|in progress|roadmap|planned\b|TODO/i`
   The scroll animation itself is not unit-testable — the content contract is.
4. **Build primitives** (one file): `Reveal`, `Spine`, `Chapter`, `Panel`,
   `Arrow`, a card-grid helper. Then a decorative background, a visuals file,
   chapter files, and a thin `index` shell. Respect the app's file-size lint
   caps by splitting chapters into 2–3 files.
5. **Register the route as public** (outside auth guards), header with wordmark
   + "Log in", hero + closing CTA.
6. **Verify visually**: run the dev server, scroll the whole page in the browser,
   screenshot each scrubbed chapter mid-scrub. Check the sticky stage pins, tiers
   highlight in sequence, and nothing dead-zones.
7. **Report the architecture review**: writing the page is an audit. In the
   final summary, list (a) claims that needed zero embellishment (architecture
   holding up), (b) where the narrative outran the build (a de-facto scope list),
   (c) tensions the writing exposed (e.g. a claim that a planned change would
   break). This is half the value of the exercise.

## Animation grammar (framer-motion)

- **Reveal** — `whileInView` fade/slide, `viewport={{ once: true, margin:
  '0px 0px -15% 0px' }}`, ease `[0.22, 1, 0.36, 1]`, stagger siblings by
  `i * 0.08`.
- **Spine** — fixed 1px rail on the left; fill is `useScroll().scrollYProgress`
  through `useSpring` driving `scaleY`, `transformOrigin: top`. Hide on mobile
  and under reduced motion.
- **Scroll-scrubbed chapters** — at most 2–3 per page; pick the flows with real
  sequence (a pipeline's stages, an escalation ladder, a chain being built).
  Pattern: a `~200vh` section, `position: sticky` stage pinned below the header,
  `useScroll({ target: ref, offset: ['start 0.7', 'end 0.6'] })` +
  `useMotionValueEvent` mapping progress → an index or 0–1 prop. The visual must
  be **pure progress → style** so it scrubs both directions.
- **Reduced motion is load-bearing**: every animated component takes a
  `useReducedMotion()` branch rendering a fully legible static variant (scrubbed
  chapters render their "complete" state). This is the accessibility story AND
  what the jsdom test renders.
- **Decorative substrate**: full-page fixed SVG behind everything, themed to the
  product's motif (circuit traces, spreadsheet cells, …). Geometry from a seeded
  PRNG (mulberry32) at module load so it is deterministic across renders and
  tests. `aria-hidden`, `pointer-events: none`, radial-gradient mask so it stays
  in the gutters. Animate with SMIL (`animateMotion` / `animate`) — cheap, no JS.
  Drop the animated layer under reduced motion.

## Gotchas (each cost a debug cycle — don't repeat them)

- **jsdom setup**: stub `IntersectionObserver` and `matchMedia` — have
  `matchMedia` report `prefers-reduced-motion` as **matched**, so tests exercise
  the static variants and never touch scroll machinery.
- **`useScroll` target refs must always be attached.** Hooks run in both
  branches, so the reduced-motion early-return must still render a wrapper with
  the ref — otherwise framer throws "Target ref is defined but not hydrated"
  as an unhandled error mid-test-run.
- **react-refresh lint** (`only-export-components`): shared data arrays live in
  a separate `content.js`, not exported from a component file.
- **Instant jumps** (End key, anchor links) can outpace `whileInView` — content
  reveals on the next scroll tick. Known, acceptable; don't chase it.
- Test heading assertions with `getByRole('heading', { name })` — chapter titles
  often recur in body text, and role queries dodge the duplicates.
- Keep body-text term assertions **case-insensitive**; card headings get
  capitalised during copy-editing and shouldn't break the contract.

## Embed the product's real components

The strongest visuals are the app's own components with canned props — the UI
users actually work in, not illustrations of it (sapphire's `BranchCard` review
list; cellform's schema editor / suggestion card / chart renderer / data table).

- **Presentational components** (cards, badges, tables, charts that take props):
  embed fully interactive against local `useState` — an accept/apply that flips
  the card state locally is a delightful, safe demo. Mark each with a small
  "the real X — try it" chip so readers know it isn't a mockup.
- **Full pages** (forms wired to routing + API): embed **display-only** — a
  framed viewport with `pointer-events: none`, scaled (`transform: scale(.75)`
  at `133%` width), height-clipped with a bottom fade — so a Save button can
  never fire a real request from a public page. If the page reads its initial
  data from `location.state`, add an optional prop that takes precedence
  (one line, no behaviour change) rather than nesting a `MemoryRouter` —
  React Router forbids a Router inside a Router.
- Canned props should echo the page's other examples (the same schema as the
  YAML card, the same filter as the ops chapter) so the chapters visibly agree.
- Extend the content-contract test: assert one distinctive string per embed,
  using role queries for buttons that repeat elsewhere on the page.

## Design notes

- Use the host app's existing tokens/typography — the page should feel like the
  product's own voice, not a bolted-on marketing site. H1 `clamp(32px, 5vw, 52px)`,
  H2 `clamp(24px, 3.5vw, 34px)`, ledes ~15–16px at max-width ~640px, chapters at
  max-width ~880px with 88–128px vertical rhythm.
- Eyebrows: mono, uppercase, letter-spaced, accent colour.
- Flow rows (Panel → Arrow → Panel) collapse to a column with rotated arrows on
  mobile; card grids collapse to one column.
- Real domain examples in the visuals (an actual-looking YAML schema, a plausible
  diff, named ops with realistic notes) — never lorem-ipsum-grade filler.
