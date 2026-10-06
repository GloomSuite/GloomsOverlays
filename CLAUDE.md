# Gloom's Overlays — project guide

> **▶ PART OF THE GLOOM SUITE.** Gloom's Overlays is unified with Gloom's Auras + Gloom's Bars
> under a shared base addon, **GloomsHub** (`~/GloomsHub`). All cross-cutting suite facts —
> the plan, current phase status, and shared runtime contracts (design tokens, the tabbed-
> shell API, the media resolver) — live THERE and are the single source of truth; this repo
> does not keep its own copy. **Before any *suite* work read `~/GloomsHub/docs/BACKLOG.md`
> first, then SUITE-STATE.md (settled state), FINDINGS.md (unproven diagnosis) and
> CONTRACTS.md as needed.** Normal Overlays-only work
> (the overlay engine, conditions, spritesheets, bugs) proceeds here as usual.
> **Gloom's Build Barn is NOT in the suite.**

> ## ★★ ONE PROJECT, FOUR REPOS — the owner works from `~/GloomsHub`
> **He opens GloomsHub and nothing else, ever.** All four suite repos are in every session's
> working directories, so this repo gets edited from a Hub session routinely — **that is correct,
> not a violation. Never tell him to close a project and open another one.**
>
> **The rule (rewritten 2026-07-26, replacing "stop and switch"):** before any change, decide which
> repo OWNS it and **say so in one line, up front**. Then get his go-ahead and do it from wherever
> you are. The goal is that no cross-repo edit happens *silently* — not that he moves.
>
> **Belongs HERE (`~/GloomsOverlays`):** the overlay engine, conditions, spritesheets, the asset browser drawer, the contents of the Overlays tab.
> **Belongs in `~/GloomsHub`:** the Suite window + tab API · the shared `LibGloomSkin` toolkit
> (tokens, widgets, `UI.*`) · media registration/catalog/resolver + the Media tab · the one minimap
> launcher · the suite docs and backlog.
> **Belongs in `~/GloomsBars` / `~/GloomsAuras`:** anything about those tools.
> **Test:** changes how ONE tool looks/behaves → that tool's repo. Changes something all three
> share, or the window they live in → the Hub.
>
> **★ Working on this repo from a Hub session? Read THIS file first** — and `docs/HANDOFF.md` for
> anything substantial. These hold the frozen decisions that do NOT load automatically from
> elsewhere, and they are the walls that stop a settled question being reopened.
>
> **No permission needed for:** updating the Hub's suite docs (required after suite work — just say
> you're doing it) · a shared-contract change plus its consumers in one pass · read-only cross-repo
> grepping. **Ambiguous?** Say so and recommend; don't guess silently, don't stall.
> Full rule + ownership table: `~/GloomsHub/CLAUDE.md`.

Bespoke WoW addon: renders cosmetic texture overlays on screen, shown/hidden by simple
conditions (always / in combat / out of combat / target selected / while casting), with
rotation, spin, tint, flip, blend mode, layer (all 9 stratas + a numeric level within one),
alpha, and spritesheet animation. Target:
**Midnight 12.1** (Interface `120100`), retail only.

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

## ★ GLOOM'S UI (2026-09-29/30) — Overlays + Portraits, and groups

**This addon is "Gloom's UI" (gloomUI, `/gui`; `/go` and `/gp` still work).** The FOLDER stays
`GloomsOverlays` (the rule above). The owner's decisions, not to be reopened:
- **A portrait is an overlay TYPE** — `ov.kind = "portrait"` (`unit` player | target, `mode` 3d | 2d,
  `size`, the camera `facing zoom modelYOffset pitch`), drawn by **`GloomsOverlays_Portraits.lua`**
  (Gloom's Portraits' delve-measured instance handling, unchanged — Hub FINDINGS §17). ONE position
  (no separate 3D / 2D places). The old Portraits settings were NOT carried over (the owner).
- **Groups** (`profile.groups`: id, name, x, y, collapsed, `attach`, `hideWithAnchor`, `scale`): a
  member's x / y are its offset from the group's anchor, times the group's `scale`. **Attach To** pins
  the group to a frame another tool offers (the Hub's ANCHORS — Unit Frames' Player / Target Frame);
  everything is placed through `GloomsOverlays_Place(ov)` → (frame, x, y), and `GloomsOverlays_Pos`
  is only for converting (Move to Group / Attach keep a thing where it is on screen).
- **On screen while the windows are open:** the selected overlay wears a lime outline, its group a
  green box; drag either. **The arrow keys nudge** the group (Group section open) or the overlay
  (Size & Position open) — the Hub's `nudge` hook, 1 px / Shift 10.
- **The eye decides both ways while the windows are open** (Auras' rule, 2026-09-30): lit shows,
  unlit HIDES — even an Always Visible overlay.
- **The last selection** is remembered per character and profile in `VibeOverlayDBChar.lastPick`
  (never in the profile — selecting must not be an undo step).
- **Undo** is the Hub's (the `undo` block at the end of `GloomsOverlays_Pages.lua`).
- **A group can be switched OFF** (`g.enabled == false`, 2026-09-30 — "a whole UI setup" kept while
  another is tried): every member is off in play, settings kept; while the windows are open the eyes
  decide, and the switch sets the members' eyes too. `GloomsOverlays_GroupOff(ov)`.
- **A new overlay starts at its image's size** (`ov.autoSize`, `FitToImage` in the pages, the Hub's
  `GloomsHub:TextureSize`): its FIRST texture sets Width / Height (one frame's for a sheet), only while
  still 200 × 200. Once.
- **The texture browser is the Hub's** (`GloomsHub:PickTexture`, gloomMEDIA → Game Textures); the
  Texture field's Browse and Browse Assets open it. `ov.sheet` (a spritesheet's grid) is set in
  Overlay & Texture → Spritesheet or carried in by the browser.

- **Visibility (2026-10-01 → 04):** **Show When** Any | All (`condMatch = "all"`); **Hide When
  Mounted** (`hideMounted`, PLAYER_MOUNT_DISPLAY_CHANGED) wins over the conditions; the checkboxes sit
  under the note however it wraps. **A GROUP has the same** (`g.condition` — nil = gates nothing —
  `g.condMatch`, `g.hideMounted`) as a GATE in front of every member: a member shows only while its
  group's AND its own conditions pass (Auras' group-load rule; the owner agreed 2026-10-04). Engine:
  `CondPass` in `GloomsOverlays.lua`.

## ★ 2026-10-06 — flipbook Direction, multi-select, reorder
- **Direction** on the Spritesheet block (`ov.sheet.dir`); playback = the Hub's `GloomsHub:SheetFrame`.
- **Multi-select**: shift-click (`toggleMulti`); `GloomsOverlays_SetMulti / Multi / NudgeMulti` — lime
  brackets move the set (÷ each member's group scale); the eye shows members; a list drag carries the
  set; any `Select` ends it. Hub BACKLOG 26 changes it next (edits to all; Shift = range, Alt = one).
- **Reorder**: a drop on an item row lands before / after it — the profile's `overlays` ARRAY is the
  order (`place()` in `P.itemDragStop`); a lilac `P.dropLine` shows where.

## ★ 2026-10-05 — what a group adds to a member's Visibility
`GloomsOverlays_GroupRuleWords(g)` (nil when the group limits nothing — an "Always Visible" under Any
counts as nothing) and `GloomsOverlays_NeverShows(ov)` (EXACT: tries all eight combat / target /
casting states, a target portrait needs a target). The Visibility section shows a lime note, or a
coral one when the member can never show / its group is off; the list line gets the coral warn icon.

## The windows (2026-09-27, the two-window design) — `GloomsOverlays_Pages.lua`

The settings are **`GloomsOverlays_Pages.lua`** (`SKIN_NEEDS = 17`), built without a mock from the
Auras / Unit Frames pages: the selector lists the profile's overlays (eye · right-click Rename /
Duplicate / Delete · New Overlay · Browse Assets), the tab names the overlay, and five sections —
Overlay & Texture · Size & Position (Width/Height with a proportions bracket, `ov.lockAspect` /
`ov.aspect`) · Rotation & Motion · Layer · Visibility. The profile block is in the Hub's Global Settings.
`GloomsOverlays_Editor.lua` (the old tab) is **out of the TOC — delete it once the owner approves.**
It carried the "SKIN_NEEDS stays at 4" decision; that reasoning died with it (the pages need 17).
`UI.RegisterColorProvider` is still guarded with `if` in the pages.

**The eye** (the owner, 2026-09-27, as Auras'): `ov.preview` is the overlay's saved eye while NOT
selected; the selected overlay shows while the windows are open whatever that says, and its eye
toggles only that (`GloomsOverlays_SetPick`, `GloomsOverlays_ToggleEye`, `GloomsOverlays_EyeOn` in the
engine; `GloomsOverlays_SetPreview(on)` from the windows' open/close). ON/OFF is the Visibility
section's switch (`ov.enabled`). The old asset browser (`_Preview.lua`) is OUT of the TOC — delete it
once the owner approves (the Hub's texture browser replaced it). `/go debug` prints each overlay's saved
and real size and scale, and Unit Frames' health display beside them.

## Conventions
- Namespace: globals are `GloomsOverlays_*` (engine API) — `VibeOverlay*` survives ONLY in the
  two SavedVariables names above.
- Design language: the shared Gloom language via **`LibGloomSkin-1.0`** (bright purple
  `#936bff` on near-black navy, Khand titles + GeneralSans body, sliding switches, no native
  Blizzard chrome). Do not hand-maintain a local toolkit copy — that is the drift the suite
  exists to remove. Tokens + widget surface: `~/GloomsHub/docs/CONTRACTS.md` §4.
- Config renders **only** in the Hub's two-window Suite (the `overlays` tool, `windows = true`)
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
