# Gloom's Overlays — project guide

> **▶ PART OF THE GLOOM SUITE.** Gloom's Overlays is unified with Gloom's Auras + Gloom's Bars
> under a shared base addon, **GloomsHub** (`~/GloomsHub`). All cross-cutting suite facts —
> the plan, current phase status, and shared runtime contracts (design tokens, the tabbed-
> shell API, the media resolver) — live THERE and are the single source of truth; this repo
> does not keep its own copy. **Before any *suite* work read `~/GloomsHub/docs/HANDOFF.md`
> first, then SUITE-STATE.md / SUITE-PLAN.md / CONTRACTS.md.** Normal Overlays-only work
> (the overlay engine, conditions, spritesheets, bugs) proceeds here as usual.
> **Gloom's Build Barn is NOT in the suite.**

> ## ★★ ROUTE THE REQUEST BEFORE YOU DO THE WORK (the owner, 2026-07-25)
> **All four suite repos are in the session's working directories, so a request aimed at another
> repo can be silently fulfilled from here. Don't let that happen.** Before starting any change,
> decide which repo OWNS it. **If it isn't this one, STOP and say so BEFORE editing anything** —
> name the repo, say in one line what it would touch, and let the owner switch. Do not "just do it
> from here", do not make a partial edit first, do not quietly edit across repos.
>
> **Belongs HERE (`~/GloomsOverlays`):** the overlay engine, conditions, spritesheets, the asset
> browser drawer, the contents of the Overlays tab.
> **Belongs in `~/GloomsHub`:** the Suite window/shell + tab API · the shared `LibGloomSkin` toolkit
> (tokens, widgets, `UI.*`) · media registration/catalog/resolver + the Media tab · the one minimap
> launcher · the suite docs + phase ledger.
> **Belongs in `~/GloomsBars` / `~/GloomsAuras`:** anything about those tools.
> **Test:** changes how ONE tool looks/behaves → that tool's repo. Changes something all three share,
> or the window they live in → the Hub.
>
> **Carve-outs (correct, not violations):** updating the Hub's SUITE-STATE ledger from here is
> *required* after suite work — just say you're doing it; a shared-contract change must update its
> consumers in the same session (say which repos up front); and read-only cross-repo grepping is
> always fine — the rule is about WRITING. **Ambiguous?** Say so, recommend, don't guess silently.
> Full rule + ownership table: `~/GloomsHub/CLAUDE.md`.

Bespoke WoW addon: renders cosmetic texture overlays on screen, shown/hidden by simple
conditions (always / in combat / out of combat / target selected / while casting), with
rotation, spin, tint, flip, blend mode, layer (all 9 stratas + a numeric level within one),
alpha, and spritesheet animation. Target:
**Midnight 12.0.7** (Interface `120007`), retail only.

Formerly **VibeOverlay** — renamed in suite Phase E (2026-07-24). The `Vibe` name is retired
and must not come back in anything user-visible. `/vibe` is gone; the slash is **`/go`**.

## ⚠ THE ONE THING THAT MUST NOT BE "TIDIED UP"

**`VibeOverlayDB` and `VibeOverlayDBChar` are the SavedVariables globals and they STAY.**

WoW keys SavedVariables off the addon FOLDER name. The Phase E rename means the client
looks for `WTF/…/SavedVariables/GloomsOverlays.lua`, so those save files were **copied**
from the `VibeOverlay.lua` ones (account level + 22 characters, 23 files total). Keeping the
global names unchanged is exactly what lets those copies load as-is with zero Lua migration.

Renaming them looks like harmless cleanup and is silent data loss:
- The account file holds every profile and every favorite (~35 KB).
- The 22 per-character files hold **which profile that character is on** — and 12 of them are
  on a non-Default profile (`Goldset` ×2, `Empty` ×10). Reset those and characters
  deliberately set to `Empty` start rendering overlays again.

The original `VibeOverlay.lua` save files are still on disk untouched as the rollback. If the
globals ever *do* get renamed, it needs a real migration shim, not a find-and-replace.

## Conventions
- Namespace: globals are `GloomsOverlays_*` (engine API) — `VibeOverlay*` survives ONLY in the
  two SavedVariables names above.
- Design language: the shared Gloom language via **`LibGloomSkin-1.0`** (bright purple
  `#936bff` on near-black navy, Khand titles + GeneralSans body, sliding switches, no native
  Blizzard chrome). Do not hand-maintain a local toolkit copy — that is the drift the suite
  exists to remove. Tokens + widget surface: `~/GloomsHub/docs/CONTRACTS.md` §4.
- Config renders **only** inside the Hub's Suite window, as the `overlays` tab
  (`GloomsHub:RegisterTab`). Hard dependency on GloomsHub, no standalone fallback window,
  no minimap button (the suite has ONE launcher — the Hub's GS button). Locked decisions.
- Media names resolve through `GloomsHub:ResolveAssetPath` — never `StoneTweaks_*`.
- Plain frames, plain SavedVariables, no Ace3.

## Testing / release
Symlinked into the client at `…/Interface/AddOns/GloomsOverlays`. QA by the owner (non-dev): ONE
copy-paste step at a time, verify before claiming, BugSack error text first.
**★ `/reload` is enough, including for NEW files (the owner, 2026-07-25)** — the old
"new files/assets → FULL CLIENT RESTART" rule is RETIRED suite-wide — **except FONTS, which
WoW loads at launch and `/reload` genuinely cannot refresh.** Home of record is
GloomsHub's `docs/HANDOFF.md` working agreement 6. Ships via BigWigs packager → GitHub Releases (repo
`GloomSuite/GloomsOverlays`), WoWup.
