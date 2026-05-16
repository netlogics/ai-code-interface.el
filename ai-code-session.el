;;; ai-code-session.el --- Lightweight AI session registry -*- lexical-binding: t; -*-

;; Author: Kang Tu <tninja@gmail.com>
;; SPDX-License-Identifier: Apache-2.0

;;; Commentary:
;; This library tracks active AI coding sessions and exposes a small query/update
;; API used by higher-level session UIs such as the dashboard.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(declare-function magit-get-current-branch "magit-git" ())
(declare-function magit-git-lines "magit-git" (&rest args))

(cl-defstruct ai-code-session
  id
  buffer
  backend
  repo-root
  task-file
  created-at
  updated-at
  metadata)

(defvar ai-code-session--sessions (make-hash-table :test 'equal)
  "Hash table mapping AI session ids to `ai-code-session' objects.")

(defvar ai-code-session--next-id 0
  "Counter used to generate lightweight AI session ids.")

(defun ai-code-session--generate-id ()
  "Return a new AI session id."
  (format "S%s" (cl-incf ai-code-session--next-id)))

(defun ai-code-session--normalize-backend (backend)
  "Return BACKEND normalized for storage."
  (cond
   ((symbolp backend) (symbol-name backend))
   ((stringp backend) backend)
   (t nil)))

(defun ai-code-session--normalize-directory (directory)
  "Return DIRECTORY normalized as an absolute directory path."
  (when (and (stringp directory)
             (not (string-empty-p directory)))
    (file-name-as-directory (expand-file-name directory))))

(defun ai-code-session--normalize-file (file)
  "Return FILE normalized as an absolute file path."
  (when (and (stringp file)
             (not (string-empty-p file)))
    (expand-file-name file)))

(defun ai-code-session--find-by-buffer (buffer)
  "Return the session object associated with BUFFER, or nil."
  (when (buffer-live-p buffer)
    (cl-find-if (lambda (session)
                  (eq (ai-code-session-buffer session) buffer))
                (hash-table-values ai-code-session--sessions))))

(defun ai-code-session--merge-plists (base plist)
  "Return BASE with the plist values from PLIST applied."
  (let ((result (copy-sequence (or base '()))))
    (while plist
      (setq result (plist-put result (pop plist) (pop plist))))
    result))

(cl-defun ai-code-session-register (&key buffer backend repo-root task-file metadata id)
  "Register or update an AI session and return it.
BUFFER is the session buffer.  BACKEND, REPO-ROOT, TASK-FILE, and METADATA
describe the session.  ID is optional and mainly useful when restoring state."
  (unless (buffer-live-p buffer)
    (user-error "Cannot register session without a live buffer"))
  (let* ((now (current-time))
         (session (or (and id (gethash id ai-code-session--sessions))
                      (ai-code-session--find-by-buffer buffer))))
    (if session
        (progn
          (setf (ai-code-session-buffer session) buffer
                (ai-code-session-updated-at session) now)
          (when backend
            (setf (ai-code-session-backend session)
                  (ai-code-session--normalize-backend backend)))
          (when repo-root
            (setf (ai-code-session-repo-root session)
                  (ai-code-session--normalize-directory repo-root)))
          (when task-file
            (setf (ai-code-session-task-file session)
                  (ai-code-session--normalize-file task-file)))
          (when metadata
            (setf (ai-code-session-metadata session)
                  (ai-code-session--merge-plists
                   (ai-code-session-metadata session)
                   metadata))))
      (setq session
            (make-ai-code-session
             :id (or id (ai-code-session--generate-id))
             :buffer buffer
             :backend (ai-code-session--normalize-backend backend)
             :repo-root (ai-code-session--normalize-directory repo-root)
             :task-file (ai-code-session--normalize-file task-file)
             :created-at now
             :updated-at now
             :metadata (copy-sequence metadata)))
      (puthash (ai-code-session-id session) session ai-code-session--sessions))
    session))

(defun ai-code-session-unregister (id-or-buffer)
  "Remove the session identified by ID-OR-BUFFER from the registry."
  (when-let ((session (ai-code-session-get id-or-buffer)))
    (remhash (ai-code-session-id session) ai-code-session--sessions)))

(defun ai-code-session-get (id-or-buffer)
  "Return the registered session identified by ID-OR-BUFFER."
  (cond
   ((bufferp id-or-buffer)
    (ai-code-session--find-by-buffer id-or-buffer))
   ((and (stringp id-or-buffer)
         (not (string-empty-p id-or-buffer)))
    (gethash id-or-buffer ai-code-session--sessions))
   (t nil)))

(defun ai-code-session-list ()
  "Return the current registered AI sessions ordered by recent activity."
  (sort (copy-sequence (hash-table-values ai-code-session--sessions))
        (lambda (left right)
          (time-less-p (ai-code-session-updated-at right)
                       (ai-code-session-updated-at left)))))

(defun ai-code-session-update-metadata (id-or-buffer metadata)
  "Merge METADATA into the session identified by ID-OR-BUFFER."
  (when-let ((session (ai-code-session-get id-or-buffer)))
    (setf (ai-code-session-metadata session)
          (ai-code-session--merge-plists
           (ai-code-session-metadata session)
           metadata)
          (ai-code-session-updated-at session) (current-time))
    session))

(defun ai-code-session--status (session)
  "Return a simple status string for SESSION."
  (let ((buffer (ai-code-session-buffer session)))
    (if (and (buffer-live-p buffer)
             (when-let ((process (get-buffer-process buffer)))
               (process-live-p process)))
        "running"
      "stopped")))

(defun ai-code-session--branch (repo-root)
  "Return the current branch for REPO-ROOT, or nil."
  (when (and repo-root (file-directory-p repo-root))
    (let ((default-directory repo-root))
      (ignore-errors
        (magit-get-current-branch)))))

(defun ai-code-session--dirty-count (repo-root)
  "Return the dirty file count for REPO-ROOT, or nil."
  (when (and repo-root (file-directory-p repo-root))
    (let ((default-directory repo-root))
      (ignore-errors
        (magit-git-lines "status" "--porcelain" "--untracked-files=normal")))))

(defun ai-code-session--default-metadata (session)
  "Return refreshed metadata plist for SESSION."
  (let* ((repo-root (ai-code-session-repo-root session))
         (metadata (ai-code-session-metadata session))
         (branch (ai-code-session--branch repo-root))
         (dirty-count (ai-code-session--dirty-count repo-root)))
    (list :branch (or branch (plist-get metadata :branch))
          :status (ai-code-session--status session)
          :dirty-count (or dirty-count (plist-get metadata :dirty-count) 0))))

(defun ai-code-session-refresh ()
  "Refresh session state and return the live session list."
  (dolist (session (copy-sequence (hash-table-values ai-code-session--sessions)))
    (let ((buffer (ai-code-session-buffer session)))
      (if (not (buffer-live-p buffer))
          (ai-code-session-unregister (ai-code-session-id session))
        (ai-code-session-update-metadata
         (ai-code-session-id session)
         (ai-code-session--default-metadata session)))))
  (ai-code-session-list))

(provide 'ai-code-session)

;;; ai-code-session.el ends here
