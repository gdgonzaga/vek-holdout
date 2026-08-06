# Contributing — Adding an Architecture Page

This page documents how to add a new subsystem or reference page to the architecture docs, including the conventions we follow and the MkDocs wiring steps.

---

## Conventions

### File naming

- One file per page, under `docs/architecture/`.
- **Subsystem pages:** `kebab-case.md`, e.g. `energy.md`, `functional-rooms.md`, `debug-console.md`.
- **Reference pages:** same style, e.g. `data-schemas.md`, `debug-commands.md`.
- The filename becomes the MkDocs nav slug; keep it short and unambiguous.

### Heading levels

Each page is a standalone document with its own heading hierarchy:

| Original (single-file) | Split (per-page) |
|---|---|
| `## Subsystem: X` | `# Subsystem: X` |
| `### Section` | `## Section` |
| `#### Class: Foo` | `### Class: Foo` |

- Every page starts with a **single `#` heading** (the subsystem or page title).
- Sub-headings, class references, and flow traces follow below at `##` / `###`.
- There is no global `# Architecture — Vek: Holdout` heading on individual pages — that lives only on `index.md`.

### Content structure (subsystem page)

Every subsystem page follows this order:

1. **Title + one-paragraph description** (the GDD section it maps to, if any)
2. **Design notes** (if any — in a blockquote or bullet list)
3. `## Files` — table of `{ File, Type, Responsibility }`
4. `## Signals` — table of `{ Signal, Emitted by, Listeners, Via EventBus?, Flows }`
5. `## Flow Trace: …` — numbered step-by-step sequences (one per significant flow)
6. `## Class Reference` — per-class blocks with `{ Extends, Script, Description, Used by, Properties, Signals, Functions }`

Not every subsystem has all sections — some omit Signals or Flow Traces. Keep the order above when present.

### Cross-references

- Use `[Subsystem Name](page.md)` links when mentioning another subsystem in prose.
  - Example: `See [Build subsystem](build.md)'s grid adapter.`
- **GDD references** stay as plain text: `GDD §6.3` (no link — GDD.md is a sibling doc, not in the site).
- **External docs** (`docs/HOWTO-create-a-map.md`, `docs/VOXEL-TOOL-NOTES.md`) stay as relative paths — they resolve on GitHub.
- **Data schemas:** link to `[Data Schemas](data-schemas.md)`.
- **Tech debt items:** link to `[Tech Debt & Unimplemented](tech-debt.md)`.

### What NOT to do

- Do **not** create `## Subsystem:` headings — the page title is `#`.
- Do **not** add trailing `---` horizontal rules between sections (they were separators in the single-file layout).
- Do **not** put the `Last updated:` line on individual pages — that lives only on `index.md`.
- Do **not** hardcode content values in tables — reference the data schema.
- Do **not** re-summarize or reword existing content — the architecture doc is authoritative; copy verbatim.

---

## Template

Minimal starter for a new subsystem page. Copy this into `docs/architecture/<name>.md` and fill in each section.

```markdown
# Subsystem: <Name>

<One paragraph: what this subsystem does, which GDD section it maps to.>

**Design notes:** (optional — remove if none)
- <Key architectural decision or constraint.>

## Files

| File | Type | Responsibility |
|---|---|---|
| `<script>.gd` | Script | <What it owns; what it does NOT own.> |
| `<scene>.tscn` / `<script>.gd` | Scene/Script | <Scene structure + script responsibility.> |
| `../data/<folder>/<file>.tres` | Data | <Resource definition. See Data Schema.> |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `<signal_name>(<params>)` | `<script>.gd` | <Listeners> | Yes / No | <Which flow trace> |

*(No new signals — <subsystem> uses direct refs / existing EventBus signals.>)*

## Flow Trace: <Action name>

**Trigger:** <What kicks off this flow.>

1. <Step 1.>
2. <Step 2.>
3. <Step 3.>

**End state:** <What the world looks like when this flow completes.>

## Class Reference

### Class: <ClassName>

**Extends:** <Node / Resource / RefCounted / CharacterBody3D>
**Script:** `<script>.gd` (in `<folder>/`)
**Description:** <What it does, what it does NOT do.>
**Used by:** <Who consumes it.>
**Lifecycle:** <`_ready` wiring, if non-trivial.>

**Properties:**

| Property | Type | Description |
|---|---|---|
| `<property>` | `<type>` | <Description.> |

**Signals:**

| Signal | Description |
|---|---|
| `<signal>` | <What listeners do with it.> |

**Functions:**

| Function | Description |
|---|---|
| `<method>(<params>) -> <return>` | <What it does.> |
```

---

## Wiring it into MkDocs

After writing the page, two files need updating:

### 1. `mkdocs.yml` — nav section

Add the page to the appropriate nav group under the `nav:` key:

```yaml
nav:
  # ...
  - Subsystems:
    # ... existing entries ...
    - "<Subsystem Name>": <filename>.md    # ← add this line
```

Keep subsystems in the same order they appear in `index.md`.

### 2. `docs/architecture/index.md` — nav table

Add a row to the **Subsystems** table on the index page:

```markdown
| [<Subsystem Name>](<filename>.md) | <Subsystem> | <GDD §> |
```

### 3. Build and verify

```bash
mkdocs build --strict     # must exit 0 — catches broken links
mkdocs serve               # preview at http://localhost:8000
```

`--strict` is important: it fails on any broken `[link](target.md)` reference, so you'll know immediately if the filename in nav/index doesn't match the actual file.
