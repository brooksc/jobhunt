---
id: TASK-665
title: 'Settings → AI: model menu is not keyboard-navigable (no type-select)'
status: To Do
assignee: []
created_date: '2026-08-05 18:26'
updated_date: '2026-08-05 19:55'
labels:
  - accessibility
  - settings
  - ui
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Correction — the original report was wrong.** I filed this as "the AI provider controls are invisible to the accessibility API". They are not. The controls sit at:

```
pop up button "Provider" of group 1 of scroll area 1 of group 1 of window "AI"
pop up button "Model"    of group 1 of scroll area 1 of group 1 of window "AI"
```

Verified working: `value of pop up button "Model"` returns `deepseek/deepseek-v4-flash`, and `click menu item "<id>" of menu 1 of pop up button "Model"` selects a model directly. My traversal had started at `group 2` — the Cost Pricing section — and never inspected `group 1`, so I concluded the subtree was missing when I had simply looked in the wrong place. **VoiceOver reachability is therefore not broken**, and the earlier claim that a VoiceOver user cannot configure the AI at all was unfounded.

**What is genuinely wrong**, and all that remains of this task: the Model menu does not support **type-select**. With the menu open, a full string (`deepseek/deepseek-v4-flash`), a prefix (`deep`) and a single letter (`d`) all leave the highlight on the first entry. Standard AppKit menus jump to the typed prefix; this one ignores keystrokes.

That matters because the OpenRouter model list runs to several hundred alphabetical entries. Without type-select the only way to reach `deepseek/...` is scrolling, which is slow with a mouse and awkward with a keyboard. It is a usability defect rather than an accessibility blocker — hence dropped to low priority.

Note for anyone automating this: select models via `click menu item "<model id>" of menu 1 of pop up button "Model" ...`. Do not attempt to drive the menu with keystrokes or by clicking its scroll chevron — the chevron click dismisses the menu.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Typing a prefix with the Model menu open jumps to the first matching model
- [ ] #2 A user can select a specific model from a several-hundred-entry list without scrolling by mouse
- [ ] #3 The other settings tabs are spot-checked for the same behaviour
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Also not keyboard-navigable.** With the Model menu open, keystrokes do not reach it at all: multi-character type-select (`deepseek/deepseek-v4-flash`), a shorter prefix (`deep`), and a single letter (`d`) all leave the highlight on the first entry. Standard AppKit menus type-select; this one ignores input entirely.

That compounds the accessibility failure: the OpenRouter model list is several hundred entries long and alphabetical, so with no type-select and no AX exposure, **the only way to choose a model is to scroll it with a mouse**. A keyboard-only user cannot configure the model, and neither can any automation.

Coordinate clicking *does* open both the Provider and Model pickers, so the controls are live — they are simply invisible to AX and deaf to the keyboard. Worth checking whether these are SwiftUI `Picker`s that need an explicit `.accessibilityLabel`/`.accessibilityElement`, or whether the surrounding `Form` is collapsing the subtree.

Retracted the VoiceOver claim and the AppUITests criterion: both rested on the mistaken finding that the controls were absent from the tree. The scriptable path is `click menu item "<model id>" of menu 1 of pop up button "Model" of group 1 of scroll area 1 of group 1 of window "AI"`, which also unblocks scripted provider setup for demo recordings.
<!-- SECTION:NOTES:END -->
