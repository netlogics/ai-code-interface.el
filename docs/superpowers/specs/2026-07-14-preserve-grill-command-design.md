# Preserve Grill Command Across Prompt Editing

## Problem

The optional Grill prompt is evaluated by advice around
`ai-code--insert-prompt`, after the user has edited the main prompt.  The
current implementation decides whether to offer Grill by inspecting
`this-command`.  Minibuffer frontends such as Helm replace that value while the
prompt is edited, so the final check no longer sees commands such as
`ai-code-ask-question` and skips the Grill question even when
`ai-code-grill-me-enabled` is non-nil.

## Desired Behavior

- Continue asking `Grill me before acting?` after main prompt editing.
- Offer the question only for the four commands listed in
  `ai-code--grill-me-commands`.
- Preserve current behavior when Grill is disabled, declined, or invoked from
  an unrelated command.
- Avoid stale global state when a command completes, signals an error, or is
  cancelled.

## Design

Add an internal dynamically bound variable that records the originating Grill
command.  Install around advice on each supported entry command.  The advice
binds the internal variable for the complete dynamic extent of the command and
then invokes the original command.

Update `ai-code--grill-me-command-p` to prefer the saved origin and fall back to
`this-command`.  The fallback preserves direct calls and existing tests.  Keep
the existing advice around `ai-code--insert-prompt`; consequently, the user is
still asked only after finishing prompt editing.

Install entry-command advice idempotently and only after each command is
defined.  This matters because `ai-code-grill` can load before
`ai-code-send-command` is defined by the main `ai-code` feature.

Dynamic binding provides automatic cleanup when the command returns or exits
nonlocally, avoiding the stale-state risk of a global pending-command value.

## Testing

Add an ERT regression test whose advised command changes `this-command` to a
Helm minibuffer command before reaching the Grill check.  Verify that the saved
origin still causes the question to be reached.  Retain coverage for disabled,
declined, accepted, and unrelated-command behavior, and verify advice
installation remains idempotent.

Run the focused Grill ERT suite, the complete ERT suite, byte compilation for
the touched Emacs Lisp file, and `checkdoc` for documentation hygiene.

## Scope

Limit production changes to `ai-code-grill.el` and regression coverage to
`test/test_ai-code-grill.el`.  Do not change prompt content, supported command
names, or the timing of the Grill question.
