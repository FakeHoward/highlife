# HighLife design system

HighLife is a calm, dense Matrix messenger. Its interaction model should feel
immediately familiar to Telegram users without copying Telegram branding,
assets, or exact layouts.

## Product signature

The signature is the conversation itself: compact grouped messages, DiceBear
avatars when a Matrix avatar is missing, clear delivery state, and bot
controls that feel native to the timeline. Aiomatrix keyboards and Mini Apps
must use the same rhythm as ordinary messages rather than looking like
embedded demos.

Layout proportions follow the golden ratio (φ ≈ 1.618): the chat column
dominates, the room list is the smaller part (377px / 55px rail), and
outgoing bubbles cap at 61.8% of the pane.

## Foundation tokens

Both clients expose the same semantic roles even when their platform
implementations differ.

| Role | Light | Dark |
| --- | --- | --- |
| canvas | `#E8EEF3` | `#0E1621` |
| surface | `#FFFFFF` | `#17212B` |
| surface-muted | `#DCE6EE` | `#1C2733` |
| text | `#17212B` | `#EDF3F7` |
| text-muted | `#5A6B78` | `#8AA0B0` |
| accent | `#168ACD` | `#45AEEA` |
| accent-pressed | `#0878B7` | `#2C98D5` |
| own-message | `#DCECC8` | `#2B5278` |
| peer-message | `#FFFFFF` | `#17212B` |
| danger | `#C83E4D` | `#F06A76` |
| divider | `#D0D8E0` | `#242F3A` |

- Typography uses the platform system sans stack everywhere, including login,
  headings, empty states, and utility surfaces. Do not load remote or display
  fonts.
- Utility and event IDs: a platform monospace face with tabular figures.
- Space scale: 5, 8, 13, 21, 34 (Fibonacci, φ). 8px remains the micro-grid.
- Corner scale: 6 for controls, 10 for panels, 14 for message bubbles. Message
  grouping may tighten adjoining corners to 5.
- Motion: 120 ms feedback, 180 ms state changes, 240 ms panel transitions,
  using deceleration curves. Respect reduced-motion preferences.

## Layout

- Compact: room list and conversation are separate routes with an explicit
  back action.
- Medium: room list and conversation appear side by side.
- Expanded: a 55-pixel space rail, 377-pixel room sidebar, and conversation
  form the desktop shell. Selecting a space may reveal a compact, dismissible
  context panel above the room list; spaces never become a vertical sidebar
  section.
- Breakpoints are based on available width, never device labels.
- Conversation text is constrained for readability; background space belongs
  outside the timeline, not inside oversized cards.

## Messages

- Consecutive events from one sender group when separated by less than five
  minutes and no system/date boundary intervenes.
- Show sender identity once per group. Keep timestamps and delivery state
  available without adding a full metadata row to every bubble.
- Replies, edits, reactions, encryption state, media progress, send
  failures, and threads are first-class message states. Thread replies stay
  in a thread panel; the main timeline keeps roots and fallback previews.
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

## Identity, addresses, and composition

- Use one reusable circular avatar component for people, rooms, and spaces.
  Missing images load a DiceBear `notionists-neutral` portrait seeded from a
  hash of the Matrix ID, so the same identity keeps the same face across
  surfaces. Initials remain the last-resort fallback if the portrait fails.
- Room details show the canonical `#alias:server` address before the opaque
  room ID, with explicit copy and management actions. Alias state changes use
  dedicated timeline language.
- The composer is one fixed row: 44-pixel attachment control, flexible
  one-line textarea, and 44-pixel send control. Poll creation belongs in the
  room menu, not in the composer or slash-command suggestions.
- Login is a compact, centered, single-column form with a square `H` mark.
