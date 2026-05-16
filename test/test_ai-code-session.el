;;; test_ai-code-session.el --- Tests for ai-code-session.el -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: Apache-2.0

;;; Commentary:
;; Tests for the lightweight AI session registry.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'ai-code-session)

(defmacro ai-code-test-session--with-clean-registry (&rest body)
  "Run BODY with a fresh session registry."
  `(let ((ai-code-session--sessions (make-hash-table :test 'equal))
         (ai-code-session--next-id 0))
     ,@body))

(ert-deftest ai-code-test-session-register-reuses-existing-buffer-entry ()
  "Registering the same buffer twice should update the existing session."
  (ai-code-test-session--with-clean-registry
   (let ((buffer (get-buffer-create "*codex[test]*")))
     (unwind-protect
         (let* ((first (ai-code-session-register
                        :buffer buffer
                        :backend "codex"
                        :repo-root "/tmp/repo/"
                        :task-file "/tmp/repo/.ai.code.files/task-a.org"))
                (second (ai-code-session-register
                         :buffer buffer
                         :backend "codex"
                         :repo-root "/tmp/repo/"
                         :task-file "/tmp/repo/.ai.code.files/task-b.org")))
           (should (equal (ai-code-session-id first)
                          (ai-code-session-id second)))
           (should (= (length (ai-code-session-list)) 1))
           (should (equal (ai-code-session-task-file second)
                          "/tmp/repo/.ai.code.files/task-b.org")))
       (when (buffer-live-p buffer)
         (kill-buffer buffer))))))

(ert-deftest ai-code-test-session-refresh-populates-branch-status-and-dirty-count ()
  "Refreshing should populate simple git/process metadata."
  (ai-code-test-session--with-clean-registry
   (let ((buffer (get-buffer-create "*codex[test-refresh]*"))
         (repo-root (make-temp-file "ai-code-session-refresh-" t)))
     (unwind-protect
         (cl-letf (((symbol-function 'get-buffer-process)
                    (lambda (_buffer) 'mock-process))
                   ((symbol-function 'process-live-p)
                    (lambda (_process) t))
                   ((symbol-function 'magit-get-current-branch)
                    (lambda () "feature/dashboard"))
                   ((symbol-function 'magit-git-lines)
                    (lambda (&rest _args) 3)))
           (let ((session (ai-code-session-register
                           :buffer buffer
                           :backend "codex"
                           :repo-root repo-root
                           :task-file "/tmp/repo/.ai.code.files/task.org")))
             (ai-code-session-refresh)
             (setq session (ai-code-session-get (ai-code-session-id session)))
             (should (equal (plist-get (ai-code-session-metadata session) :branch)
                            "feature/dashboard"))
             (should (equal (plist-get (ai-code-session-metadata session) :status)
                            "running"))
             (should (= (plist-get (ai-code-session-metadata session) :dirty-count)
                        3))))
       (when (buffer-live-p buffer)
         (kill-buffer buffer))
       (when (file-directory-p repo-root)
         (delete-directory repo-root t))))))

(ert-deftest ai-code-test-session-refresh-prunes-dead-buffers ()
  "Refreshing should drop sessions whose buffers are no longer live."
  (ai-code-test-session--with-clean-registry
   (let ((buffer (get-buffer-create "*codex[test-dead]*")))
     (ai-code-session-register
      :buffer buffer
      :backend "codex"
      :repo-root "/tmp/repo/")
     (kill-buffer buffer)
     (ai-code-session-refresh)
     (should-not (ai-code-session-list)))))

(provide 'test_ai-code-session)

;;; test_ai-code-session.el ends here
