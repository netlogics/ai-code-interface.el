# Preserve Grill Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve the originating Grill-enabled command across Helm/minibuffer prompt editing so the optional Grill question appears after editing.

**Architecture:** Around advice on each supported entry command dynamically binds an internal origin variable for the command's complete execution. The existing send-time advice continues to ask after prompt editing, while command matching prefers the preserved origin and falls back to `this-command` for compatibility.

**Tech Stack:** Emacs Lisp with lexical binding, Emacs advice, ERT, byte compilation, and checkdoc.

---

### Task 1: Preserve the Originating Command

**Files:**
- Modify: `ai-code-grill.el:29-84`
- Test: `test/test_ai-code-grill.el`

- [ ] **Step 1: Write the failing regression test**

Add a test that models Helm replacing `this-command` after the main prompt is edited:

```elisp
(ert-deftest ai-code-grill-preserves-origin-across-prompt-editing ()
  (let ((ai-code-grill-me-enabled t)
        (this-command 'ai-code-ask-question)
        asked)
    (cl-letf (((symbol-function 'y-or-n-p)
               (lambda (&rest _args)
                 (setq asked t)
                 nil)))
      (ai-code--with-grill-me-origin
       (lambda ()
         (setq this-command 'helm-maybe-exit-minibuffer)
         (ai-code--maybe-add-grill-me-harness "prompt")))
      (should asked))))
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
emacs -batch -L . -l ert -l test/test_ai-code-grill.el \
  --eval "(ert-run-tests-batch-and-exit 'ai-code-grill-preserves-origin-across-prompt-editing)"
```

Expected: FAIL because `ai-code--with-grill-me-origin` is undefined.

- [ ] **Step 3: Add the dynamic origin and wrapper**

Add the internal variable after `ai-code--grill-me-commands`:

```elisp
(defvar ai-code--grill-me-origin-command nil
  "Originating interactive command for the current Grill-enabled request.")
```

Change command matching to prefer the saved origin:

```elisp
(defun ai-code--grill-me-command-p ()
  "Return non-nil when the active command should offer grill-me."
  (memq (or ai-code--grill-me-origin-command this-command)
        ai-code--grill-me-commands))
```

Add the around-advice function before `ai-code--maybe-add-grill-me-harness`:

```elisp
(defun ai-code--with-grill-me-origin (orig-fun &rest args)
  "Call ORIG-FUN with ARGS while preserving the entry command."
  (let ((ai-code--grill-me-origin-command
         (or ai-code--grill-me-origin-command this-command)))
    (apply orig-fun args)))
```

- [ ] **Step 4: Run the focused Grill tests and verify GREEN**

Run:

```bash
emacs -batch -L . -l ert -l test/test_ai-code-grill.el \
  -f ert-run-tests-batch-and-exit
```

Expected: all Grill tests pass with zero unexpected results.

- [ ] **Step 5: Commit the origin-preservation behavior**

```bash
git add ai-code-grill.el test/test_ai-code-grill.el
git commit -m "fix: preserve grill command through prompt editing"
```

### Task 2: Install Entry-Command Advice Safely

**Files:**
- Modify: `ai-code-grill.el:86-96`
- Test: `test/test_ai-code-grill.el`

- [ ] **Step 1: Write a failing idempotent-installation test**

Add a temporary supported command and verify that installing advice twice still preserves the origin without asking twice:

```elisp
(ert-deftest ai-code-grill-installs-entry-advice-idempotently ()
  (let ((ai-code--grill-me-commands '(ai-code--test-grill-entry))
        (ai-code-grill-me-enabled t)
        (this-command 'ai-code--test-grill-entry)
        (ask-count 0))
    (unwind-protect
        (progn
          (fset 'ai-code--test-grill-entry
                (lambda ()
                  (setq this-command 'helm-maybe-exit-minibuffer)
                  (ai-code--maybe-add-grill-me-harness "prompt")))
          (ai-code--install-grill-me-command-advice)
          (ai-code--install-grill-me-command-advice)
          (cl-letf (((symbol-function 'y-or-n-p)
                     (lambda (&rest _args)
                       (cl-incf ask-count)
                       nil)))
            (funcall 'ai-code--test-grill-entry))
          (should (= ask-count 1)))
      (advice-remove 'ai-code--test-grill-entry
                     #'ai-code--with-grill-me-origin)
      (fmakunbound 'ai-code--test-grill-entry))))
```

- [ ] **Step 2: Run the installation test and verify RED**

Run:

```bash
emacs -batch -L . -l ert -l test/test_ai-code-grill.el \
  --eval "(ert-run-tests-batch-and-exit 'ai-code-grill-installs-entry-advice-idempotently)"
```

Expected: FAIL because `ai-code--install-grill-me-command-advice` is undefined.

- [ ] **Step 3: Implement idempotent deferred advice installation**

Add this installer before `ai-code--install-grill-me-advice`:

```elisp
(defun ai-code--install-grill-me-command-advice ()
  "Install origin-preserving advice on available Grill commands."
  (dolist (command ai-code--grill-me-commands)
    (when (and (fboundp command)
               (not (advice-member-p #'ai-code--with-grill-me-origin command)))
      (advice-add command :around #'ai-code--with-grill-me-origin))))
```

After the existing send-time advice installation, install available entry advice and defer retries until the defining features load:

```elisp
(ai-code--install-grill-me-command-advice)

(dolist (feature '(ai-code-change ai-code-discussion ai-code))
  (with-eval-after-load feature
    (ai-code--install-grill-me-command-advice)))
```

- [ ] **Step 4: Run the focused Grill suite and verify GREEN**

Run:

```bash
emacs -batch -L . -l ert -l test/test_ai-code-grill.el \
  -f ert-run-tests-batch-and-exit
```

Expected: all Grill tests pass, and the idempotence test records exactly one question.

- [ ] **Step 5: Commit advice installation**

```bash
git add ai-code-grill.el test/test_ai-code-grill.el
git commit -m "fix: install grill entry advice after command loading"
```

### Task 3: Verify the Complete Change

**Files:**
- Verify: `ai-code-grill.el`
- Verify: `test/test_ai-code-grill.el`

- [ ] **Step 1: Run the complete ERT suite**

```bash
emacs -batch -L . -l ert \
  --eval "(mapc #'load-file (file-expand-wildcards \"test/test_*.el\"))" \
  -f ert-run-tests-batch-and-exit
```

Expected: zero unexpected ERT results.

- [ ] **Step 2: Byte-compile the touched production file**

```bash
emacs -Q --batch -L . -f batch-byte-compile ai-code-grill.el
```

Expected: exit status 0 with no new warnings. Remove the generated untracked `ai-code-grill.elc` afterward if compilation creates it beside the source.

- [ ] **Step 3: Run checkdoc on the touched files**

```bash
emacs -Q --batch -L . \
  --eval "(progn (require 'checkdoc) (checkdoc-file \"ai-code-grill.el\") (checkdoc-file \"test/test_ai-code-grill.el\"))"
```

Expected: exit status 0 with no new documentation diagnostics.

- [ ] **Step 4: Inspect the final diff and worktree scope**

```bash
git diff --check HEAD~2..HEAD
git status --short
```

Expected: no whitespace errors; only the intended Grill source/tests and previously existing unrelated untracked files are present.
