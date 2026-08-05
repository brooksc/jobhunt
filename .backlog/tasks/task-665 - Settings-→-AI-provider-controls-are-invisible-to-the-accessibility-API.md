---
id: TASK-665
title: Settings → AI provider controls are invisible to the accessibility API
status: To Do
assignee: []
created_date: '2026-08-05 18:26'
updated_date: '2026-08-05 18:34'
labels:
  - accessibility
  - settings
  - ui
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Provider row, API Key field, Model picker and **Fetch Models** button in Settings → AI do not appear in the accessibility tree at all.

Walking the Settings window (`window "AI"` → `group 1` → `scroll area 1`) yields only three heading/group pairs — Cost Pricing and Cost Estimate. Direct queries return nothing:

```
popupsInSA=0  popupsInWin=0  popupsInG2=0     (AXPopUpButton)
menu buttons in every group = none found       (AXMenuButton)
```

The controls are plainly rendered on screen and respond to synthetic clicks at their screen coordinates, so this is an exposure problem, not a rendering one.

**Why it matters beyond automation:** this is the pane where a user configures the provider and pastes an API key. If it isn't in the accessibility tree, **VoiceOver users cannot configure the app's AI at all** — which makes the core feature unreachable for them. The scripting inconvenience is the symptom; the accessibility failure is the bug.

Found while trying to script provider setup for the demo recording: the whole configuration step had to be abandoned because none of it is addressable, and even AppUITests could not assert on it today.

Contrast with the rest of the app, which is well exposed — job rows carry their text, the detail tabs are a radio group, the correction flags carry AXHelp. Something specific to how this Form/Picker is built is dropping the subtree.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Provider picker, API key field, Model picker and Fetch Models are present in the accessibility tree with usable roles
- [ ] #2 Each carries a label that identifies it without relying on adjacent static text
- [ ] #3 VoiceOver can reach and change the provider and model, and paste an API key
- [ ] #4 An AppUITests case configures a provider end-to-end through the accessibility API
- [ ] #5 The same audit is applied to the other settings tabs, which have not been checked
- [ ] #6 Type-select works in the Model menu, so a long model list is navigable without a mouse
- [ ] #7 The Model menu is fully operable by keyboard alone
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Also not keyboard-navigable.** With the Model menu open, keystrokes do not reach it at all: multi-character type-select (`deepseek/deepseek-v4-flash`), a shorter prefix (`deep`), and a single letter (`d`) all leave the highlight on the first entry. Standard AppKit menus type-select; this one ignores input entirely.

That compounds the accessibility failure: the OpenRouter model list is several hundred entries long and alphabetical, so with no type-select and no AX exposure, **the only way to choose a model is to scroll it with a mouse**. A keyboard-only user cannot configure the model, and neither can any automation.

Coordinate clicking *does* open both the Provider and Model pickers, so the controls are live — they are simply invisible to AX and deaf to the keyboard. Worth checking whether these are SwiftUI `Picker`s that need an explicit `.accessibilityLabel`/`.accessibilityElement`, or whether the surrounding `Form` is collapsing the subtree.
<!-- SECTION:NOTES:END -->
