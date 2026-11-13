# Loom

## Todo

## In Progress

## Blocked [Archived]

## Done

### Migrate to Zig 0.17.1

  - due: 2026-11-13
  - tags: [zig-0.17.1, build, types, ecs, bench]
  - priority: high
  - workload: Hard
  - defaultExpanded: false
  - steps:
      - [x] Bump `.minimum_zig_version` to `"0.17.1"` and update `raylib_zig` dependency (`@build`)
      - [x] Migrate `std.builtin.Type.Fn.Param` / `info.params` to `info.param_types` and `@Tuple` in `lm_ecs/System.zig` (`@ecs`)
      - [x] Update `std.meta.fields`, `builtin.mode`, `@splat`, and `std.Io` APIs for Zig 0.17.1 (`@types`, `@bench`)
      - [x] Verify full build and unit test suite under Zig 0.17.1 (`@build`)
    ```md
    Update the codebase, build manifest, and dependencies to target Zig `0.17.1`.
    ```

### Rename `lm_core` to `lm_types`

  - due: 2026-11-13
  - tags: [types, build, ecs, test]
  - priority: medium
  - workload: Normal
  - defaultExpanded: false
  - steps:
      - [x] Rename `lm_core` module and imports to `lm_types` in `build.zig` and `lib/root.zig` (`@build`, `@root`)
      - [x] Update all `@import("lm_core")` references across `lm_ecs`, `lm_types`, `bench`, and `test` (`@ecs`, `@types`, `@bench`, `@test`)
    ```md
    Rename the core types module from `lm_core` to `lm_types` to better reflect its responsibility.
    ```

### Extract `lm_benchmarking` Module

  - due: 2026-11-13
  - tags: [benchmarking, build, types]
  - priority: medium
  - workload: Normal
  - defaultExpanded: false
  - steps:
      - [x] Remove `benchmarking` re-export from `lm_types/root.zig` (`@types`)
      - [x] Register `lm_benchmarking` in `build.zig` and export it from `lib/root.zig` (`@build`, `@root`)
      - [x] Migrate `lm_benchmarking/root.zig` to `std.Io.Writer`, `std.Io.Timestamp`, warmup, and trial hooks (`@bench`)
      - [x] Re-implement `bench/lm_ecs/root.zig` and `bench/root.zig` using `lm_benchmarking` (`@bench`)
      - [x] Add `test/lm_benchmarking/test.zig` unit tests (`@test`)
    ```md
    Extract benchmarking into its own standalone `lm_benchmarking` module with updated Zig 0.17.1 I/O and timing APIs.
    ```

### Overhaul `lm_uuid` Module

  - due: 2026-11-13
  - tags: [uuid, test]
  - priority: medium
  - workload: Normal
  - defaultExpanded: false
  - steps:
      - [x] Implement `core`, `urn`, `v4`, `v5`, and `v7` UUID generation and serialization (`@uuid`)
      - [x] Add unit tests in `test/lm_uuid/test.zig` and wire into `test/test.zig` (`@test`)
    ```md
    Overhaul `lm_uuid` with RFC 9562 v4/v5/v7 support, safe URN serialization/deserialization, and unit test coverage.
    ```

### v0.11.0: Asset Pipeline, ECS Buffer Cache & Animator Sprite Cache

  - due: 2026-10-26
  - tags: [v0.11.0, ecs, assets, builtin-components]
  - priority: high
  - workload: Hard
  - defaultExpanded: false
  - steps:
      - [x] Migrate `Behaviour` from `std.c.malloc` to use a `[]u8` buffer for caching (`@ecs`)
      - [x] Rework the `assets.zig` module into modular caches (`@assets`)
      - [x] Add `Animator` sprite cache (`@builtin-components`)
    ```md
    - **Assets Goal**: Modularize asset caching and stream/manage assets with reference counting and cache eviction hooks.
    - **Animator Goal**: When a playing animation changes the sprites of an entity, store the textures in a cache to prevent unnecessary disk reads.
    ```

### v0.9.1: Quality of Life Improvements

  - due: 2026-02-06
  - tags: [v0.9.1, root, types, ecs, builtin-components]
  - priority: medium
  - workload: Normal
  - defaultExpanded: false
  - steps:
      - [x] Add `lm.deprecate` (`@root`)
      - [x] Add `lm.assert` and `lm.assertFmt` (`@root`)
      - [x] Deprecate `lm.summon` in favor of `lm.summoning` (`@root`)
      - [x] Remove `SharedPointer` in favor of internal `RefCounter` in `lm.assets` (`@types`)
      - [x] Fix `ecs/Behaviour` `memccpy` -> `memcpy` memory bug (`@ecs`)
      - [x] Fix typo in `builtin-components/collision.zig` (`@builtin-components`)
      - [x] Improve readability of `eventloop/Scene.zig`
    ```md
    Fix bugs and improve the quality of life while using `loom`. `SharedPointer` was removed and replaced by an internal `RefCounter` implementation used by `lm.assets`.
    ```

### v0.9.0: Unit Tests

  - due: 2025-10-21
  - tags: [v0.9.0, release, test]
  - priority: high
  - workload: Hard
  - defaultExpanded: false
  - steps:
      - [x] Add unit tests for `List(T)` (`@test`)
      - [x] Add unit tests for `Array(T)` and remove `Array(T).fromTuple()` (`@test`)
      - [x] Add unit tests for the ECS (`@test`)
      - [x] Fix `SharedPointer(T)` and add unit tests (`@test`)
      - [x] Add `Scene` unit tests (`@test`)
      - [x] Add `SceneController.zig` unit tests (`@test`)
    ```md
    Minor release adding unit test coverage across core data structures (`List`, `Array`), ECS, `SharedPointer`, `Scene`, and `SceneController`.
    ```

### v0.8.0 - v0.8.1: Multi-Platform Dockerfile

  - due: 2025-10-14
  - tags: [v0.8.0, v0.8.1, release, repo, tooling]
  - priority: low
  - workload: Easy
  - defaultExpanded: false
  - steps:
      - [x] Add Dockerfile to test multi-platform building
    ```md
    Minor release adding Docker support to test multi-platform builds.
    ```

### v0.7.0: The Rendering Update

  - due: 2025-09-25
  - tags: [v0.7.0, release, display]
  - priority: high
  - workload: Hard
  - defaultExpanded: false
  - steps:
      - [x] Implement new `Camera` system (`@display`)
      - [x] Add vertex and fragment shader support
      - [x] Add new camera management configuration
    ```md
    Handle multiple render contexts where each `Camera` targets its own `RenderTexture`, rendering the world at different positions to different segments of the screen.
    ```

### v0.6.0: Input Update

  - due: 2025-09-25
  - tags: [v0.6.0, release, input]
  - priority: medium
  - workload: Normal
  - defaultExpanded: false
  - steps:
      - [x] Update `input.mouse` and `input.keyboard` (`@input`)
      - [x] Add `input.gamepad` controller support (`@input`)
    ```md
    Achieve complete feature parity with Raylib's mouse and keyboard functions under `input.mouse` and `input.keyboard`, and expand controller support via `input.gamepad`.
    ```

### v0.5.0: Update to Zig v0.15.1 & Dependencies

  - due: 2025-09-23
  - tags: [v0.5.0, release, repo, types]
  - priority: medium
  - workload: Normal
  - defaultExpanded: false
  - steps:
      - [x] Update Zig version to `v0.15.1`
      - [x] Add `loom.List(T)`
    ```md
    Minor release upgrading Zig to `v0.15.1`, updating dependencies, and introducing `loom.List(T)`.
    ```

### v0.4.0: The Audio Update

  - due: 2025-06-11
  - tags: [v0.4.0, release, assets, audio]
  - priority: medium
  - workload: Normal
  - defaultExpanded: false
  - steps:
      - [x] Add audio asset streaming (`@assets`)
      - [x] Add high-level `audio` interface (`@audio`)
    ```md
    Wrap the asset handling solution in an easy-to-use `audio` module where functions take an audio path/ID and parameters without requiring manual memory or asset tracking.
    ```

### v0.3.0: Global Behaviours & Array Tests

  - due: 2025-06-11
  - tags: [v0.3.0, release, ecs, test]
  - priority: medium
  - workload: Normal
  - defaultExpanded: false
  - steps:
      - [x] Add scene-scoped global behaviours (`@ecs`)
      - [x] Add unit tests for `Array(T)` (`@test`)
    ```md
    Global behaviours are scene-scoped and tied to the executing scene rather than individual entities.
    ```

### v0.2.1: Collider Rotation Fix

  - due: 2025-06-10
  - tags: [v0.2.1, builtin-components]
  - priority: medium
  - workload: Easy
  - defaultExpanded: false
  - steps:
      - [x] Fix collider rotation

### v0.2.0: Minor Release

  - due: 2025-06-09
  - tags: [v0.2.0, release]
  - priority: low
  - workload: Easy
  - defaultExpanded: false
  - steps:
      - [x] Publish release `v0.2.0` (`@release`)

### v0.1.4: ECS & Project Configuration Cleanup

  - due: 2025-06-09
  - tags: [v0.1.4, ecs, root, repo]
  - priority: medium
  - workload: Normal
  - defaultExpanded: false
  - steps:
      - [x] Fix `removeComponent` (`@ecs`)
      - [x] Update `project(void)(void)` to `project(ProjectConfig)(void)` (`@root`)
      - [x] Clean up `root.zig` (`@root`)
      - [x] Update `README.md` to use `#stable` branch as package base (`@repo`)

### v0.1.3: Y-Index Display Sorting

  - due: 2025-06-09
  - tags: [v0.1.3, display, examples]
  - priority: medium
  - workload: Normal
  - defaultExpanded: false
  - steps:
      - [x] Add display sorting based on Y-index (`@display`)
      - [x] Add example for Z-Y display sorting (`@examples`)

### v0.1.2: Comptime Prefabs & Install Instructions

  - due: 2025-06-09
  - tags: [v0.1.2, ecs, repo]
  - priority: medium
  - workload: Normal
  - defaultExpanded: false
  - steps:
      - [x] Change `Prefab` definitions to be comptime (`@ecs`)
      - [x] Update `README.md` with install instructions (`@repo`)
    ```md
    Prefabs are always comptime-known schematics for building an entity. For runtime spawning, use `loom.makeEntity()` or `loom.makeEntityI()` to immediately obtain an `Entity`.
    ```

### v0.1.1: Summoning Fix

  - due: 2025-06-09
  - tags: [v0.1.1, ecs]
  - priority: medium
  - workload: Easy
  - defaultExpanded: false
  - steps:
      - [x] Fix entity summoning implementation

### v0.1.0: Collision System Rewrite

  - due: 2025-06-06
  - tags: [v0.1.0, builtin-components]
  - priority: high
  - workload: Hard
  - defaultExpanded: false
  - steps:
      - [x] Rewrite collision system

