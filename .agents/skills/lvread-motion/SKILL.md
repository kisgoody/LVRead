---
name: lvread-motion
description: Implement appropriate native UIKit animation in the LVRead iOS project. Use automatically when creating or modifying Swift files under LVRead/LVRead/UI, especially screens, reusable views, navigation, reader transitions, loading, empty, error, selection, expansion, insertion, deletion, settings, and other visible state changes. Do not use for pure model, parser, repository, networking, persistence, localization, or documentation changes unless they directly change a user-visible UI state.
---

# LVRead Motion

Add restrained, useful motion as part of the requested UI implementation. Do not stop at recommending animation.

## Workflow

1. Use CodeGraph first when `.codegraph/` exists. Inspect the touched view or controller, its callers, and nearby animation patterns before editing.
2. Animate only when motion clarifies direct feedback, state change, hierarchy, or spatial continuity. Leave static presentation changes unanimated.
3. Reuse the existing architecture, theme values, and animation helpers. Keep reader page-turn behavior in `LVRead/LVRead/UI/Reader/Animation`; do not duplicate `PageFlipAnimator`, `PaperCurlAnimator`, `SlideAnimator`, or `CoverAnimator` behavior elsewhere.
4. Implement the smallest native UIKit solution that works. Do not add dependencies or SwiftUI.
5. Keep model and navigation state independent of animation completion. Handle repeated input without leaving stale transforms, alpha, constraints, snapshots, or disabled interaction.
6. Build or run the narrowest relevant test after editing. For visual changes, inspect the affected screen when the environment supports it and state any verification limitation.

## UIKit Choices

- Use `UIView.animate` for simple alpha, transform, color, or constraint transitions.
- Use `UIViewPropertyAnimator` for interactive, interruptible, or reversible motion.
- Use `UIView.transition` for a short cross-dissolve between equivalent states.
- Animate Auto Layout changes by updating constraints before calling `layoutIfNeeded()` inside the animation block.
- Include `.beginFromCurrentState` and `.allowUserInteraction` when an action can repeat before completion.
- Use Core Animation only when UIKit animation APIs cannot express the required effect.

## Motion Rules

- Direct feedback: 0.12-0.20 seconds.
- Content or state transition: 0.20-0.30 seconds.
- Reader page turns: preserve the existing animator configuration and gesture progress.
- Prefer ease-out for entering, ease-in for leaving, and platform defaults for navigation.
- Avoid decorative entrance animation, infinite pulse, bounce, large scale changes, and delays that block user action unless explicitly required.
- Avoid snapshotting large views outside the existing reader animation path.

## Accessibility

Check `UIAccessibility.isReduceMotionEnabled` for translation, scale, rotation, parallax, spring, and page-turn effects. In reduced-motion mode, update immediately or use a cross-dissolve no longer than 0.18 seconds. Preserve VoiceOver focus and never communicate state through motion alone.

## Completion Report

State where motion was added, why it helps, how reduced motion behaves, and what verification ran. If no animation is warranted, say so briefly instead of adding decorative motion.
