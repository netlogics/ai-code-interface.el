;;; test_ai-code-grill.el --- Tests for ai-code-grill -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'ai-code-grill)

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
