# HighLife design system

HighLife is a calm, dense Matrix messenger. Its interaction model should feel
immediately familiar to Telegram users without copying Telegram branding,
assets, or exact layouts.

## Product signature

The signature is the conversation itself: compact grouped messages, clear
delivery state, and bot controls that feel native to the timeline. Aiomatrix
keyboards and Mini Apps must use the same rhythm as ordinary messages rather
than looking like embedded demos.

## Foundation tokens

Both clients expose the same semantic roles even when their platform
implementations differ.

| Role | Light | Dark |
| --- | --- | --- |
| canvas | `#F4F6F8` | `#101418` |
| surface | `#FFFFFF` | `#182027` |
| surface-muted | `#E9EEF2` | `#202A32` |
| text | `#17212B` | `#EDF3F7` |
| text-muted | `#667786` | `#91A2AF` |
| accent | `#168ACD` | `#45AEEA` |
| accent-pressed | `#0878B7` | `#2C98D5` |
| own-message | `#DDF2FD` | `#164A66` |
| peer-message | `#FFFFFF` | `#202A32` |
| danger | `#C83E4D` | `#F06A76` |
| divider | `#D9E0E5` | `#2B3740` |

- Body typography: a highly legible system sans stack. Avoid branding the
  product with a generic display-font hero inside the app shell.
- Utility and event IDs: a platform monospace face with tabular figures.
- Space scale: 4, 8, 12, 16, 24, 32.
- Corner scale: 6 for controls, 10 for panels, 14 for message bubbles. Message
  grouping may tighten adjoining corners to 5.
- Motion: 120 ms feedback, 180 ms state changes, 240 ms panel transitions,
  using deceleration curves. Respect reduced-motion preferences.

## Layout

- Compact: room list and conversation are separate routes with an explicit
  back action.
- Medium: room list and conversation appear side by side.
- Expanded: an optional thread or room-info panel may join the two-pane shell.
- Breakpoints are based on available width, never device labels.
- Conversation text is constrained for readability; background space belongs
  outside the timeline, not inside oversized cards.

## Messages

- Consecutive events from one sender group when separated by less than five
  minutes and no system/date boundary intervenes.
- Show sender identity once per group. Keep timestamps and delivery state
  available without adding a full metadata row to every bubble.
- Replies, edits, reactions, threads, encryption state, media progress, and
  send failures are first-class message states.
- Inline keyboards align with their parent bubble and use rectangular controls
  with restrained radii. Primary and destructive styles are semantic, not
  decorative.

## Interaction and accessibility

- Every action has hover, pressed, disabled, loading, error, and keyboard-focus
  behavior where the platform supports it.
- Touch targets are at least 44 logical pixels while visual controls may remain
  compact.
- Do not communicate delivery, encryption, errors, or selected state using
  color alone.
- Empty states explain the next useful action. Errors identify what failed and
  how to retry.
- Avoid persistent blur, decorative gradients, glass cards, excessive pills,
  and motion that does not communicate a state change.
