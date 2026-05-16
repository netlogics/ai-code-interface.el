;;; ai-code-session-dashboard.el --- Dashboard for AI sessions -*- lexical-binding: t; -*-

;; Author: Kang Tu <tninja@gmail.com>
;; SPDX-License-Identifier: Apache-2.0

;;; Commentary:
;; This library provides a simple tabulated-list dashboard for active AI coding
;; sessions tracked by `ai-code-session'.

;;; Code:

(require 'subr-x)
(require 'tabulated-list)
(require 'ai-code-session)

(declare-function magit-status "magit-status" (&optional directory))
(declare-function magit-status-setup-buffer "magit-status" (directory))

(defconst ai-code-session-dashboard-buffer-name "*AI Code Sessions*"
  "Buffer name used by the AI session dashboard.")

(defun ai-code-session-dashboard--repo-name (session)
  "Return a short repository name for SESSION."
  (when-let ((repo-root (ai-code-session-repo-root session)))
    (file-name-nondirectory (directory-file-name repo-root))))

(defun ai-code-session-dashboard--task-name (session)
  "Return a display task file name for SESSION."
  (when-let ((task-file (ai-code-session-task-file session)))
    (file-name-nondirectory task-file)))

(defun ai-code-session-dashboard--backend-label (backend)
  "Return a human-friendly label for BACKEND."
  (let ((text (cond
               ((symbolp backend) (symbol-name backend))
               ((stringp backend) backend)
               (t ""))))
    (capitalize (replace-regexp-in-string "[-_]+" " " text))))

(defun ai-code-session-dashboard--entry (session)
  "Return the `tabulated-list-mode' entry for SESSION."
  (let* ((metadata (ai-code-session-metadata session))
         (branch (or (plist-get metadata :branch) ""))
         (status (or (plist-get metadata :status) ""))
         (dirty-count (number-to-string (or (plist-get metadata :dirty-count) 0))))
    (list (ai-code-session-id session)
          (vector
           (ai-code-session-id session)
           (or (ai-code-session-dashboard--repo-name session) "")
           (or (ai-code-session-dashboard--task-name session) "")
           (ai-code-session-dashboard--backend-label
            (ai-code-session-backend session))
           branch
           status
           dirty-count))))

(defun ai-code-session-dashboard--entries ()
  "Return dashboard entries for all active sessions."
  (mapcar #'ai-code-session-dashboard--entry
          (ai-code-session-refresh)))

(defun ai-code-session-dashboard--session-at-point ()
  "Return the dashboard session at point."
  (ai-code-session-get (tabulated-list-get-id)))

(defun ai-code-session-dashboard-refresh ()
  "Refresh the AI session dashboard."
  (interactive)
  (setq tabulated-list-entries (ai-code-session-dashboard--entries))
  (tabulated-list-print t))

(defun ai-code-session-dashboard-visit ()
  "Visit the session buffer on the current line."
  (interactive)
  (if-let* ((session (ai-code-session-dashboard--session-at-point))
            (buffer (ai-code-session-buffer session))
            ((buffer-live-p buffer)))
      (pop-to-buffer buffer)
    (user-error "No live AI session on this line")))

(defun ai-code-session-dashboard-kill-session ()
  "Kill the session on the current line, after confirmation when needed."
  (interactive)
  (let* ((session (or (ai-code-session-dashboard--session-at-point)
                      (user-error "No AI session on this line")))
         (buffer (ai-code-session-buffer session))
         (process (and (buffer-live-p buffer) (get-buffer-process buffer))))
    (when (and process
               (process-live-p process)
               (not (y-or-n-p (format "Kill AI session %s? "
                                      (ai-code-session-id session)))))
      (user-error "Session kill canceled"))
    (when (and process (process-live-p process))
      (delete-process process))
    (when (buffer-live-p buffer)
      (kill-buffer buffer))
    (ai-code-session-unregister session)
    (ai-code-session-dashboard-refresh)))

(defun ai-code-session-dashboard-open-diff ()
  "Open Magit status for the repository on the current line."
  (interactive)
  (if-let* ((session (ai-code-session-dashboard--session-at-point))
            (repo-root (ai-code-session-repo-root session)))
      (magit-status-setup-buffer repo-root)
    (user-error "No repository is associated with this session")))

(defvar ai-code-session-dashboard-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map (kbd "RET") #'ai-code-session-dashboard-visit)
    (define-key map (kbd "r") #'ai-code-session-dashboard-refresh)
    (define-key map (kbd "g") #'ai-code-session-dashboard-refresh)
    (define-key map (kbd "k") #'ai-code-session-dashboard-kill-session)
    (define-key map (kbd "D") #'ai-code-session-dashboard-open-diff)
    map)
  "Keymap used by `ai-code-session-dashboard-mode'.")

(define-derived-mode ai-code-session-dashboard-mode tabulated-list-mode "AI Sessions"
  "Major mode for the AI session dashboard."
  (setq tabulated-list-format
        [("Session" 10 t)
         ("Repo" 18 t)
         ("Task file" 24 t)
         ("Backend" 14 t)
         ("Branch" 20 t)
         ("Status" 12 t)
         ("Dirty files" 11 t)])
  (setq tabulated-list-padding 2)
  (add-hook 'tabulated-list-revert-hook #'ai-code-session-dashboard-refresh nil t)
  (tabulated-list-init-header))

;;;###autoload
(defun ai-code-session-dashboard ()
  "Show the AI session dashboard."
  (interactive)
  (let ((buffer (get-buffer-create ai-code-session-dashboard-buffer-name)))
    (with-current-buffer buffer
      (ai-code-session-dashboard-mode)
      (ai-code-session-dashboard-refresh))
    (pop-to-buffer buffer)))

(provide 'ai-code-session-dashboard)

;;; ai-code-session-dashboard.el ends here
