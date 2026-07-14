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

(provide 'test-ai-code-grill)

;;; test_ai-code-grill.el ends here
