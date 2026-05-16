;;; test_ai-code-session-dashboard.el --- Tests for ai-code-session-dashboard.el -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: Apache-2.0

;;; Commentary:
;; Tests for the AI session dashboard UI.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'ai-code-session-dashboard)

(defmacro ai-code-test-session-dashboard--with-clean-state (&rest body)
  "Run BODY with a fresh dashboard/session state."
  `(let ((ai-code-session--sessions (make-hash-table :test 'equal))
         (ai-code-session--next-id 0))
     ,@body))

(defun ai-code-test-session-dashboard--goto-first-entry ()
  "Move point to the first dashboard entry."
  (goto-char (point-min))
  (re-search-forward "^S[0-9]+" nil t)
  (beginning-of-line))

(ert-deftest ai-code-test-session-dashboard-renders-mvp-columns ()
  "Dashboard should render the MVP session information."
  (ai-code-test-session-dashboard--with-clean-state
   (let ((session-buffer (get-buffer-create "*codex[demo]*"))
         (repo-root (make-temp-file "ai-code-dashboard-demo-" t))
         dashboard-buffer)
     (unwind-protect
         (progn
           (ai-code-session-register
            :buffer session-buffer
            :backend "codex"
            :repo-root repo-root
            :task-file "/tmp/demo-repo/.ai.code.files/task_x.org"
            :metadata '(:branch "feature/x" :status "running" :dirty-count 3))
           (cl-letf (((symbol-function 'get-buffer-process)
                      (lambda (_buffer) 'mock-process))
                     ((symbol-function 'process-live-p)
                      (lambda (_process) t))
                     ((symbol-function 'magit-get-current-branch)
                      (lambda () "feature/x"))
                     ((symbol-function 'magit-git-lines)
                      (lambda (&rest _args) '("a" "b" "c")))
                     ((symbol-function 'pop-to-buffer)
                      (lambda (buffer &rest _args)
                        (setq dashboard-buffer buffer)
                        (get-buffer-window buffer))))
             (ai-code-session-dashboard))
           (with-current-buffer dashboard-buffer
             (should (derived-mode-p 'ai-code-session-dashboard-mode))
             (should (equal (length tabulated-list-entries) 1))
             (let ((entry (cadar tabulated-list-entries)))
               (should (equal (aref entry 1)
                              (file-name-nondirectory
                               (directory-file-name repo-root))))
               (should (equal (aref entry 2) "task_x.org"))
               (should (equal (aref entry 3) "Codex"))
               (should (equal (aref entry 4) "feature/x"))
               (should (equal (aref entry 5) "running"))
               (should (equal (aref entry 6) "3")))))
       (when (buffer-live-p session-buffer)
         (kill-buffer session-buffer))
       (when (file-directory-p repo-root)
         (delete-directory repo-root t))
       (when (buffer-live-p dashboard-buffer)
         (kill-buffer dashboard-buffer))))))

(ert-deftest ai-code-test-session-dashboard-visit-switches-to-session-buffer ()
  "RET should jump to the selected session buffer."
  (ai-code-test-session-dashboard--with-clean-state
   (let ((session-buffer (get-buffer-create "*codex[visit]*"))
         (repo-root (make-temp-file "ai-code-dashboard-visit-" t))
         dashboard-buffer
         visited-buffer)
     (unwind-protect
         (progn
           (ai-code-session-register
            :buffer session-buffer
            :backend "codex"
            :repo-root repo-root
            :metadata '(:status "running" :dirty-count 0))
           (cl-letf (((symbol-function 'get-buffer-process)
                      (lambda (_buffer) 'mock-process))
                     ((symbol-function 'process-live-p)
                      (lambda (_process) t))
                     ((symbol-function 'pop-to-buffer)
                      (lambda (buffer &rest _args)
                        (if (eq buffer session-buffer)
                            (setq visited-buffer buffer)
                          (setq dashboard-buffer buffer))
                        (get-buffer-window buffer))))
             (ai-code-session-dashboard)
             (with-current-buffer dashboard-buffer
               (ai-code-test-session-dashboard--goto-first-entry)
               (ai-code-session-dashboard-visit))
             (should (eq visited-buffer session-buffer))))
       (when (buffer-live-p session-buffer)
         (kill-buffer session-buffer))
       (when (file-directory-p repo-root)
         (delete-directory repo-root t))
       (when (buffer-live-p dashboard-buffer)
         (kill-buffer dashboard-buffer))))))

(ert-deftest ai-code-test-session-dashboard-open-diff-uses-magit-status ()
  "D should open `magit-status' for the session repository."
  (ai-code-test-session-dashboard--with-clean-state
   (let ((session-buffer (get-buffer-create "*codex[diff]*"))
         (repo-root (make-temp-file "ai-code-dashboard-diff-" t))
         dashboard-buffer
         opened-repo)
     (unwind-protect
         (progn
           (ai-code-session-register
            :buffer session-buffer
            :backend "codex"
            :repo-root repo-root
            :metadata '(:status "running" :dirty-count 0))
           (cl-letf (((symbol-function 'get-buffer-process)
                      (lambda (_buffer) 'mock-process))
                     ((symbol-function 'process-live-p)
                      (lambda (_process) t))
                     ((symbol-function 'pop-to-buffer)
                      (lambda (buffer &rest _args)
                        (setq dashboard-buffer buffer)
                        (get-buffer-window buffer)))
                     ((symbol-function 'magit-status-setup-buffer)
                      (lambda (directory)
                        (setq opened-repo directory))))
             (ai-code-session-dashboard)
             (with-current-buffer dashboard-buffer
               (ai-code-test-session-dashboard--goto-first-entry)
               (ai-code-session-dashboard-open-diff))
             (should (equal opened-repo
                            (file-name-as-directory repo-root)))))
       (when (buffer-live-p session-buffer)
         (kill-buffer session-buffer))
       (when (file-directory-p repo-root)
         (delete-directory repo-root t))
       (when (buffer-live-p dashboard-buffer)
         (kill-buffer dashboard-buffer))))))

(ert-deftest ai-code-test-session-dashboard-kill-session-removes-registry-entry ()
  "Killing a running dashboard session should unregister it."
  (ai-code-test-session-dashboard--with-clean-state
   (let ((session-buffer (get-buffer-create "*codex[kill]*"))
         (repo-root (make-temp-file "ai-code-dashboard-kill-" t))
         dashboard-buffer
         process)
     (unwind-protect
         (progn
           (setq process (start-process "ai-code-dashboard-kill" session-buffer
                                        "sleep" "60"))
           (set-process-query-on-exit-flag process nil)
           (ai-code-session-register
            :buffer session-buffer
            :backend "codex"
            :repo-root repo-root
            :metadata '(:status "running" :dirty-count 0))
           (cl-letf (((symbol-function 'y-or-n-p)
                      (lambda (&rest _args) t))
                     ((symbol-function 'pop-to-buffer)
                      (lambda (buffer &rest _args)
                        (setq dashboard-buffer buffer)
                        (get-buffer-window buffer))))
             (ai-code-session-dashboard)
             (with-current-buffer dashboard-buffer
               (ai-code-test-session-dashboard--goto-first-entry)
               (ai-code-session-dashboard-kill-session))
             (should-not (ai-code-session-list))
             (should-not (buffer-live-p session-buffer))
             (should-not (process-live-p process))))
       (when (and process (process-live-p process))
         (delete-process process))
       (when (buffer-live-p session-buffer)
         (kill-buffer session-buffer))
       (when (file-directory-p repo-root)
         (delete-directory repo-root t))
       (when (buffer-live-p dashboard-buffer)
         (kill-buffer dashboard-buffer))))))

(provide 'test_ai-code-session-dashboard)

;;; test_ai-code-session-dashboard.el ends here
