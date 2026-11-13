---
name: aesthetic
description: 'Enforce clean code style and software design principles based on CodeAesthetic: anti-nesting (Never-Nester, max 3 indentation levels), explicit naming without abbreviations, quantities with explicit units, domain-specific organization over utils, minimal coupling over premature abstraction, and self-documenting code. Use when writing, reviewing, or refactoring code.'
metadata:
  tags: "Code Style, Architecture, Clean Code, Anti-Nesting, Naming, Refactoring"
  category: "engineering"
---

# Code Style and Software Design Principles

Adhere strictly to CodeAesthetic engineering principles across all code changes, refactors, and architectural designs. Write expressive, decoupled, and human-readable code.

## Persistence

These principles apply to every code modification, new file creation, and refactoring task across the entire codebase. They do not lapse between turns or tasks.

## What drives these principles

Four engineering realities drive every rule below:

1. **Reading vastly exceeds writing.** Abbreviations and cryptic names force mental decoding. Clear names eliminate cognitive drag.
2. **Coupling is the equal and opposite reaction to abstraction.** Premature abstractions lock subsystems together and are far more painful than a little duplicated code.
3. **Deep nesting exceeds human working memory.** Every indentation level adds an active mental condition. Flat, sequential logic is easier to reason about and debug.
4. **Internal comments rot and lie.** Code changes; comments stay behind. Clean, expressive code documents itself through types, predicates, and structure.

## Rules

### 1. Never abbreviate names

Never shorten identifiers. Modern IDEs provide instant autocompletion and wide screens. Abbreviations provide zero architectural value.

- **Strictly Prohibited**: `pos`, `idx`, `cnt`, `cur`, `len`, `btn`, `calc`, `mgr`, `dir`, `dmg`, `acc`, `vel`, `dist`, `vol`, `dt`.
- **Mandatory**: `position`, `index`, `count`, `current`, `length`, `button`, `calculate`, `manager`, `direction`, `damage`, `acceleration`, `velocity`, `distance`, `volume`, `delta_seconds`.

Bad:
```zig
fn calc_dmg(mgr: *EnemyMgr, cur_idx: usize, pos: Vec2) f32 { ... }
```

Good:
```zig
fn calculate_damage(manager: *EnemyManager, current_index: usize, position: Vector2) f32 { ... }
```

### 2. Ban single-letter variable names

Single-letter variables obscure what data represents. Always use descriptive names for loops, iterators, and closure captures.

- **Allowed Exception**: Standard mathematical coordinate axes (`vector.x`, `vector.y`, `vector.z`) when referencing 2D/3D vectors.

Bad:
```zig
for (enemies) |e| { ... }
for (items, 0..) |it, i| { ... }
```

Good:
```zig
for (enemies) |enemy| { ... }
for (items, 0..) |item, item_index| { ... }
```

### 3. Quantities with units must encode the unit

When a variable represents a physical dimension, temporal duration, or rate, always suffix the unit in the variable name (unless represented by a strongly typed unit type).

- **Bad**: `delay`, `timeout`, `speed`, `radius`, `reload_time`.
- **Good**: `delay_seconds`, `timeout_ms`, `speed_pixels_per_second`, `radius_pixels`, `reload_cooldown_seconds`.

### 4. No Hungarian notation or types in names

Do not put data types into variable names ("No Hungarian notation") or type names ("No types in your types").

- **Variable Names**: Avoid `enemy_ptr`, `health_int`, `player_object`, `bullets_array`, `name_str`. Use `target_enemy`, `current_health`, `player`, `active_bullets`, `player_name`.
- **No Interface Prefixes**: Do not prefix interfaces with `I` (e.g., avoid `IEnemy`, `IWeapon`, `IInteractable`).
- **No Base/Abstract Suffixes/Prefixes**: Do not name parent structs `BaseEnemy` or `AbstractController`. Keep the canonical noun for the parent (`Enemy`) and over-specify specialized children (`MeleeEnemy`, `BossEnemy`).

### 5. Eliminate utils and helper junk drawers

A file or struct named `utils.zig` or `helpers.zig` is an anti-pattern indicating structural laziness. Eliminate grab bags through three strategies:

1. **Move to Target Type**: If a function operates on a specific type, make it a method on that type.
2. **Create Domain Collections**: If functions manipulate a group of objects, wrap them in a domain struct (e.g., `EnemyGroup`, `RoomGrid`).
3. **Extract Dedicated Modules**: If functionality is truly reusable, extract it into a focused, single-responsibility module (e.g., `Paginator.zig`, `Easing.zig`, `DevicePrompts.zig`).

### 6. Anti-nesting: Never-Nester rule (Max 3 levels)

Functions must never exceed **3 levels of indentation**. 4 levels of indentation is strictly prohibited. Flatten logic using two techniques:

1. **Inversion (Guard Clauses & Early Returns)**: Check exit/failure conditions at the top of the function ("validation gatekeeping") and return or continue early.
2. **Extraction**: Extract complex loop bodies or orchestrator routines into small, sequential functions with single responsibilities.

Bad (4 levels deep):
```zig
pub fn process_attack(self: *Self, target: ?*Enemy) void {
    if (target) |enemy| {
        if (enemy.is_alive()) {
            if (!self.is_on_cooldown) {
                if (self.mana >= 10) {
                    self.mana -= 10;
                    enemy.apply_damage(self.attack_damage);
                }
            }
        }
    }
}
```

Good (Inversion with guard clauses):
```zig
pub fn process_attack(self: *Self, maybe_target: ?*Enemy) void {
    const enemy = maybe_target orelse return;
    if (!enemy.is_alive()) return;
    if (self.is_on_cooldown) return;
    if (self.mana < 10) return;

    self.mana -= 10;
    enemy.apply_damage(self.attack_damage);
}
```

### 7. Abstraction vs. coupling: The Rule of Three

A little code repetition is far less painful than the wrong abstraction. Shared abstractions rigidly couple subsystems together.

- **Do NOT abstract if**: It only saves a few lines of trivial assignment, couples structs to an identical input signature, or removes a single duplicated call behind an `if`.
- **Abstract ONLY when**:
  1. **Rule of Three**: There are **three or more** distinct implementations sharing meaningful structural behavior.
  2. **Separation of Decision from Execution**: Decoupling *which* concrete implementation is selected from *when or how* it executes.

### 8. Self-documenting code over internal comments

Write code that explains itself through names, types, and structure rather than relying on natural-language comments.

- **Replace Magic Numbers**: Use descriptive constants or enums instead of raw numbers.
- **Decompose Boolean Logic**: Assign complex conditions to descriptive boolean predicates (`is_within_range`, `is_hostile`).
- **Use Strong Types**: Prefer optional types (`?T`) over sentinel values like `-1`.
- **Public API Documentation**: Use doc comments (`///`) at module and function boundaries for public contracts.
- **Internal Comments**: Narrative comments inside function bodies explaining *what* code does are strictly discouraged.

## When to break the rules

Override default restrictions only in these specific scenarios:

1. **Single-Letter Variables**: Standard 2D/3D coordinate axes (`vector.x`, `vector.y`, `vector.z`) when operating directly on coordinate vectors.
2. **Internal Comments (WHY, never WHAT)**:
   - *Non-obvious performance optimizations* (e.g., SIMD layout, cache alignment).
   - *External algorithmic citations* (citing papers, math formulas, or reference links).
   - *Platform/engine bug workarounds* (documenting a known driver or OS defect).
3. **Indentation depth edge cases**: When third-party library macros or Zig comptime constructs force an indentation level, extract the inner block immediately to keep the rest flat.

## Pre-commit check

Before submitting or approving code changes, verify:

1. **Indentation**: Are all functions at or below 3 indentation levels?
2. **Abbreviations**: Are prohibited abbreviations (`pos`, `idx`, `cnt`, `cur`, `len`, `btn`, `calc`, `mgr`, `dir`, `dmg`, `vel`) completely replaced?
3. **Single Letters**: Are all loop and closure variables named descriptively?
4. **Units**: Do all temporal and physical quantities include explicit unit suffixes (`_seconds`, `_pixels`, `_ms`)?
5. **No Junk Drawers**: Are there any new `utils` or `helpers` files or structs?
6. **Comments**: Do internal comments explain *why* (if any of the 3 exceptions apply), rather than *what*?
7. **Build**: Does `zig build` succeed with exit code 0?
