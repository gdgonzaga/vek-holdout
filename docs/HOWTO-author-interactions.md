# How To: Author an Interaction

> End-to-end guide for adding an E-key interaction to a piece of furniture —
> from the GameAction that runs, through the Conditions that gate it, to wiring
> it into a `FurnitureDef`. Covers the data-driven `.tres` authoring flow the
> runtime (`InteractionComponent` + `InteractionUI`) consumes.
>
> **Prerequisites:** familiar with Godot Resources and the inspector. Read
> `docs/architecture/actions.md` first for the subsystem overview; schemas live
> in `docs/architecture/data-schemas.md`.

---

## How the chain fits together

A furniture interaction is four `.tres` resources layered together:

```
FurnitureDef (e.g. data/furniture/workbench.tres)
└── action_options: Array[ActionOption]
    └── ActionOption        (data/action_options/<id>.tres)
        ├── action:    GameAction     (data/actions/<id>.tres)  ← what happens
        └── conditions: Array[Condition]                        ← gating (optional)
            └── Condition / AnyOf / AllOf / NotCondition / leaves
```

- **`GameAction`** — "what happens" when the player picks the option (override
  `execute(actor, target)`).
- **`Condition`** — gates the option; its `is_met(actor, target)` decides
  whether the menu button is enabled.
- **`ActionOption`** — one menu button. Binds a `GameAction` to zero-or-more
  `Condition`s.
- **`FurnitureDef.action_options`** — the list of options a furniture offers.
  Empty (the default) means **non-interactable**.

At spawn, `FurnitureLayer` copies the def's `action_options` onto an
`InteractionComponent` child (named exactly `"InteractionComponent"`) on the
furniture node. The player's crosshair raycast resolves that component; pressing
E opens the menu; clicking a button runs the action.

> **Only `FurnitureDef` carries `action_options`.** `BlockDef` (voxel blocks)
> has no equivalent — blocks resolve through the voxel grid, not as `Node3D`
> instances.

---

## Step 1: Write a GameAction

A `GameAction` is a `Resource` with a `label` (button text) and a virtual
`execute(actor, target)`.

1. Create `data/actions/<id>_action.gd`:

   ```gdscript
   class_name OpenCraftAction
   extends GameAction

   func execute(actor: Node, target: Node) -> void:
       # `actor` is the player; `target` is the furniture node.
       print("Open crafting UI for %s" % target.name)
   ```

   (`actor` / `target` are typed `Node` on the base; your override can keep them
   untyped or upcast as needed.)

2. Create the matching `.tres`: in the editor, **New Resource → OpenCraftAction**
   (or your `class_name`), save as `data/actions/open_craft_action.tres`. Set
   `label` to the button text (e.g. `"Craft"`).

The existing smoke-test is `data/actions/print_action.gd` /
`print_action.tres` (`PrintAction` prints `"Action executed"`) — copy it as a
starting point.

---

## Step 2 (optional): Author Conditions

A `Condition` is a `Resource` with a virtual `is_met(actor, target) -> bool`.
Three composites already exist in `subsystems/actions/`:

| Class | File | Semantics |
|---|---|---|
| `AnyOf` | `any_of.gd` | true if **any** child `is_met`. |
| `AllOf` | `all_of.gd` | true only if **all** children `is_met` (redundant inside an `ActionOption`, which already ANDs its conditions). |
| `NotCondition` | `not.gd` | inverts a single child (`condition`, not `conditions`). |

To use one, create a `.tres` of that class and populate its `conditions` (or
`condition` for `NotCondition`) array.

> **Leaf conditions exist.** `data/conditions/` ships `MinSkillCondition`
> (`skill_id` + `min_level` — gates on the actor's skill), `HasItemCondition`
> (`item_id` or `item_tag` + `count` — gates on the actor's inventory), and
> `CanCarryDispensedItems` (dispenser capacity check), plus authored
> `true.tres` / `false.tres` constants. Combine them with the composites above.
> An option with an empty `conditions` array is always available.

To author a new gate kind (e.g. "is daytime"), write a leaf `Condition`
subclass in `data/conditions/`, then reference its `.tres` from the
`ActionOption`.

---

## Step 3: Author an ActionOption

An `ActionOption` binds one `GameAction` to its gating `Condition`s.

1. In the editor, **New Resource → ActionOption**, save as
   `data/action_options/<id>.tres` (the directory exists — ten options ship
   there today).
2. In the inspector:
   - Drag your `GameAction.tres` from Step 1 into the **Action** field.
   - Drag zero-or-more `Condition.tres` from Step 2 into the **Conditions**
     array.

The button will be enabled only when **all** listed conditions are met (AND).
Leave `Conditions` empty for an always-available option.

---

## Step 4: Wire it into a FurnitureDef

1. Open the furniture's `FurnitureDef.tres` (e.g.
   `data/furniture/workbench.tres`). Currently its `action_options` is empty,
   so it is non-interactable.
2. Drag your `ActionOption.tres` from Step 3 into the **Action Options** array.
   Add as many options as the furniture should offer (one button each).
3. Save. Nothing else needs wiring — `FurnitureLayer.spawn` reads
   `action_options`, attaches an `InteractionComponent`, and copies the array
   verbatim.

> **`BlockDef` has no `action_options`.** If you want a voxel block to be
> interactable, that requires a different mechanism (out of scope here) — the
> interaction chain only applies to `FurnitureDef`.

---

## Step 5: Test in-game

1. Run the project, place the furniture (Build mode → select it → LMB), exit
   Build mode.
2. Point the crosshair at the furniture — the HUD's **InteractLabel** under the
   crosshair shows the target's name and action hint.
3. Press **E**. A pop-up menu appears with:
   - A **label** at the top — the furniture's `display_name` (resolved via the
     `Furniture.label` getter, which returns `def.display_name`).
   - One **button** per `ActionOption`, text from `option.action.label`.
     Buttons whose conditions fail are disabled (greyed out).
4. Click a button. The bound `GameAction.execute` runs (e.g. `PrintAction`
   prints `"Action executed"` to the console), and the menu closes.
5. Press **Esc** to close the menu without taking an action.

If the menu doesn't appear, see Troubleshooting below.

---

## Troubleshooting

- **Pressing E does nothing.** Either (a) you're in Blueprint mode (interaction
  is skipped when `mode != NORMAL` — exit with Esc), (b) the furniture has no
  `InteractionComponent` (its `FurnitureDef.action_options` is empty — see
  Step 4), or (c) `_current_interactable` is null because the raycast hit
  nothing within `interact_distance` (8.0).
- **No `InteractionComponent` spawned.** `FurnitureLayer` only attaches one when
  `def is FurnitureDef` **and** `action_options` is non-empty. A plain
  `BuildableDef` (e.g. `pole`) or a `BlockDef` will never get one. Confirm the
  def is a `FurnitureDef` and the array is populated.
- **`InteractionComponent` exists but isn't found.** The child must be named
  **exactly** `"InteractionComponent"` — this is hard-coded in
  `Player._find_interaction_component`. `FurnitureLayer` sets this name when it
  creates the node; if you hand-place a component in a scene, match the name.
- **Menu mounts on the wrong layer.** `InteractionComponent._open_interaction_ui`
  prefers a CanvasLayer in the `"hud_layer"` group, falling back to `"ui_layer"`.
  In the shipped `main.tscn` **both** layers carry their groups (`HUDLayer` is in
  `"hud_layer"`, `UILayer` in `"ui_layer"`), so the menu mounts on the HUDLayer.
- **Button is disabled when it shouldn't be.** Check the option's `conditions` —
  every condition's `is_met` must return `true`. Remember `ActionOption`
  ANDs its conditions, and `AllOf` inside an option is redundant.
- **Action runs but nothing visible happens.** `PrintAction` only `print()`s —
  check the console. Your own `GameAction.execute` must do the real work
  (open a UI, modify state, emit a signal, etc.).
- **Conditions don't re-block after the menu opens.** Conditions are evaluated
  **once** when the menu is built (they set each button's `disabled` state).
  They are not re-checked at execute time. If a condition must block execution
  after the menu is open, the `GameAction` itself must re-validate.
