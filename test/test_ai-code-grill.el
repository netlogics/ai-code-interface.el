;;; test_ai-code-grill.el --- Tests for ai-code-grill -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'ai-code-prompt-mode)
(require 'ai-code-grill)

(defun ai-code-grill-test--clean-emacs-result (form)
  "Run FORM in a clean batch Emacs and return its exit code and output."
  (let* ((emacs (expand-file-name invocation-name invocation-directory))
         (root (file-name-as-directory
                (expand-file-name default-directory)))
         (stubs (expand-file-name "test/stubs" root)))
    (with-temp-buffer
      (let ((exit-code
             (call-process emacs nil (current-buffer) nil
                           "-Q" "--batch"
                           "-L" root
                           "-L" stubs
                           "--eval" form)))
        (list exit-code (buffer-string))))))

(ert-deftest ai-code-grill-autoloaded-entry-loads-grill ()
  "Loading an autoloaded entry module should install Grill advice."
  (pcase-let
      ((`(,exit-code ,output)
        (ai-code-grill-test--clean-emacs-result
         (concat
          "(progn "
          "(setq load-prefer-newer t) "
          "(load \"ai-code-autoloads.el\" nil nil t) "
          "(require 'ai-code-change) "
          "(unless (and (featurep 'ai-code-grill) "
          "(advice-member-p #'ai-code--with-optional-grill-me "
          "'ai-code--insert-prompt) "
          "(advice-member-p #'ai-code--with-grill-me-origin "
          "'ai-code-code-change)) "
          "(kill-emacs 1)))"))))
    (should (equal exit-code 0))
    (should-not (string-match-p "Error:" output))))

(ert-deftest ai-code-grill-disabled-keeps-prompt ()
  (let ((ai-code-grill-me-enabled nil)
        (this-command 'ai-code-code-change))
    (should (equal (ai-code--maybe-add-grill-me-harness "prompt")
                   "prompt"))))

(ert-deftest ai-code-grill-ignores-other-commands ()
  (let ((ai-code-grill-me-enabled t)
        (this-command 'ai-code-explain))
    (cl-letf (((symbol-function 'y-or-n-p)
               (lambda (&rest _args)
                 (ert-fail "Should not ask for unrelated commands"))))
      (should (equal (ai-code--maybe-add-grill-me-harness "prompt")
                     "prompt")))))

(ert-deftest ai-code-grill-declined-keeps-prompt ()
  (let ((ai-code-grill-me-enabled t)
        (this-command 'ai-code-ask-question))
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _args) nil)))
      (should (equal (ai-code--maybe-add-grill-me-harness "prompt")
                     "prompt")))))

(ert-deftest ai-code-grill-accepted-appends-reference ()
  (let ((ai-code-grill-me-enabled t)
        (this-command 'ai-code-send-command))
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _args) t))
              ((symbol-function 'ai-code--grill-me-reference-suffix)
               (lambda () "Read @prompt/grilling.v1.md")))
      (should (equal (ai-code--maybe-add-grill-me-harness "prompt")
                     "prompt\nRead @prompt/grilling.v1.md")))))

(ert-deftest ai-code-grill-direct-command-bypasses-question ()
  "A direct slash command should bypass Grill unchanged."
  (let ((ai-code-grill-me-enabled t)
        (this-command 'ai-code-send-command))
    (cl-letf (((symbol-function 'y-or-n-p)
               (lambda (&rest _args)
                 (ert-fail "Direct commands should not ask about Grill"))))
      (should (equal (ai-code--maybe-add-grill-me-harness "/status")
                     "/status")))))

(ert-deftest ai-code-grill-whitespace-slash-prompt-remains-eligible ()
  "A slash-prefixed prompt with whitespace should remain Grill-eligible."
  (let ((ai-code-grill-me-enabled t)
        (this-command 'ai-code-send-command))
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _args) t))
              ((symbol-function 'ai-code--grill-me-reference-suffix)
               (lambda () "Read @prompt/grilling.v1.md")))
      (should
       (equal
        (ai-code--maybe-add-grill-me-harness "/review this file")
        "/review this file\nRead @prompt/grilling.v1.md")))))

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
            (funcall (symbol-function 'ai-code--test-grill-entry)))
          (should (= ask-count 1)))
      (advice-remove 'ai-code--test-grill-entry
                     #'ai-code--with-grill-me-origin)
      (fmakunbound 'ai-code--test-grill-entry))))

(ert-deftest ai-code-grill-installs-entry-advice-after-late-command-loading ()
  (let ((was-fboundp (fboundp 'ai-code-send-command))
        (original-function (when (fboundp 'ai-code-send-command)
                             (symbol-function 'ai-code-send-command)))
        (original-features features)
        (after-load-alist (copy-tree after-load-alist))
        (ai-code--grill-me-commands '(ai-code-send-command)))
    (unwind-protect
        (progn
          (setq features (delq 'ai-code (copy-sequence features)))
          (fset 'ai-code-send-command (lambda (&optional _arg)))
          (provide 'ai-code)
          (should (advice-member-p #'ai-code--with-grill-me-origin
                                   'ai-code-send-command)))
      (setq features original-features)
      (advice-remove 'ai-code-send-command #'ai-code--with-grill-me-origin)
      (if was-fboundp
          (fset 'ai-code-send-command original-function)
        (fmakunbound 'ai-code-send-command)))))

(provide 'test-ai-code-grill)

;;; test_ai-code-grill.el ends here
