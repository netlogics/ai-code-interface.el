;;; ai-code-grill.el --- Optional prompt clarification harness -*- lexical-binding: t; -*-

;; Author: Kang Tu <tninja@gmail.com>

;; SPDX-License-Identifier: Apache-2.0

;;; Commentary:
;; Offer an optional one-question-at-a-time clarification harness for the main
;; prompt entry commands before their completed prompt is sent to an AI backend.

;;; Code:

(require 'subr-x)

(declare-function ai-code--git-root "ai-code-utils" (&optional dir))
(declare-function ai-code--insert-prompt "ai-code-prompt-mode" (prompt-text))

;;;###autoload
(defcustom ai-code-grill-me-enabled nil
  "When non-nil, offer to clarify selected prompts before sending them.

The prompt is offered for `ai-code-code-change', `ai-code-ask-question',
`ai-code-implement-todo', and `ai-code-send-command'.  When accepted, the
request tells the AI backend to read the bundled grilling harness before
acting."
  :type 'boolean
  :group 'ai-code)

(defconst ai-code--grill-me-commands
  '(ai-code-code-change
    ai-code-ask-question
    ai-code-implement-todo
    ai-code-send-command)
  "Interactive commands that offer the grill-me harness.")

(defun ai-code--grill-me-package-directory ()
  "Return the package installation directory for ai-code."
  (file-name-directory
   (file-truename
    (or (locate-library "ai-code")
        load-file-name
        buffer-file-name
        default-directory))))

(defun ai-code--grill-me-harness-file ()
  "Return the bundled grill-me harness file path."
  (expand-file-name "prompt/grilling.v1.md"
                    (ai-code--grill-me-package-directory)))

(defun ai-code--grill-me-prompt-path (file-path)
  "Return FILE-PATH formatted for prompt usage."
  (if-let ((git-root (ai-code--git-root)))
      (let ((git-root-truename
             (file-name-as-directory (file-truename git-root)))
            (file-truename (file-truename file-path)))
        (if (file-in-directory-p file-truename git-root-truename)
            (file-relative-name file-truename git-root-truename)
          file-path))
    file-path))

(defun ai-code--grill-me-reference-suffix ()
  "Return a short prompt suffix referencing the grill-me harness."
  (let ((file-path (ai-code--grill-me-harness-file)))
    (unless (file-readable-p file-path)
      (user-error "Grill-me harness is not readable: %s" file-path))
    (format
     "Read the local harness file: @%s. Use its instructions for this request. Apply them without repeating their full contents."
     (ai-code--grill-me-prompt-path file-path))))

(defun ai-code--grill-me-command-p ()
  "Return non-nil when the active command should offer grill-me."
  (memq this-command ai-code--grill-me-commands))

(defun ai-code--maybe-add-grill-me-harness (prompt-text)
  "Return PROMPT-TEXT, optionally with the grill-me harness reference."
  (if (and ai-code-grill-me-enabled
           (ai-code--grill-me-command-p)
           (y-or-n-p "Grill me before acting? "))
      (concat prompt-text "\n" (ai-code--grill-me-reference-suffix))
    prompt-text))

(defun ai-code--with-optional-grill-me (orig-fun prompt-text)
  "Call ORIG-FUN with PROMPT-TEXT after optional grill-me handling."
  (funcall orig-fun (ai-code--maybe-add-grill-me-harness prompt-text)))

(defun ai-code--install-grill-me-advice ()
  "Install the optional grill-me advice once."
  (unless (advice-member-p #'ai-code--with-optional-grill-me
                           'ai-code--insert-prompt)
    (advice-add 'ai-code--insert-prompt
                :around
                #'ai-code--with-optional-grill-me)))

(ai-code--install-grill-me-advice)

;;;###autoload
(with-eval-after-load 'ai-code-prompt-mode
  (require 'ai-code-grill))

(provide 'ai-code-grill)

;;; ai-code-grill.el ends here
