;;; ai-code-doc-repo-map.el --- Repository map generation for AI code interface -*- lexical-binding: t; -*-

;; Author: Kang Tu <tninja@gmail.com>
;; SPDX-License-Identifier: Apache-2.0

;;; Commentary:
;; This file provides functionality to derive a repository map document that
;; helps users and AI coding agents quickly onboard onto an unfamiliar codebase.

;;; Code:

(require 'subr-x)
(require 'ai-code-utils)
(require 'ai-code-input)
(require 'ai-code-prompt-mode)

(declare-function ai-code-plain-read-string "ai-code-input" (prompt &optional initial-input history default inherit-input-method))
(declare-function ai-code--insert-prompt "ai-code-prompt-mode" (prompt-text))
(declare-function ai-code--format-repo-context-info "ai-code-utils")
(declare-function ai-code--git-root "ai-code-utils" (&optional dir))
(declare-function ai-code--ensure-files-directory "ai-code-utils")

(defconst ai-code-repo-map-output-relative-path
  ".ai.code.files/architecture/repo-map.org"
  "Repository-relative path for the derived repository map document.")

(defun ai-code-repo-map--read-document-language ()
  "Ask the user which language they want to use in the repo map.
Default value is English."
  (let ((lang (read-string "Document language: " "English")))
    (if (string-empty-p lang) "English" lang)))

(defun ai-code-repo-map--append-document-language (base-prompt)
  "Prompt for the language and append it to BASE-PROMPT."
  (concat base-prompt
          (format "\nGenerate the document in %s."
                  (ai-code-repo-map--read-document-language))))

(defun ai-code-repo-map--ensure-document-file ()
  "Ensure the repository map Org document exists and return its path."
  (let* ((files-dir (ai-code--ensure-files-directory))
         (architecture-dir (expand-file-name "architecture" files-dir))
         (target-file (expand-file-name "repo-map.org" architecture-dir)))
    (make-directory architecture-dir t)
    (unless (file-exists-p target-file)
      (write-region "" nil target-file nil 'silent))
    target-file))

(defun ai-code-repo-map--derive-prompt (git-root)
  "Build and return a repository map derivation prompt for GIT-ROOT."
  (concat
   "Derive a lightweight Repository Map document for this existing repository.\n"
   "The primary goal is to help a new human contributor or AI coding agent quickly understand how to read and navigate the codebase.\n"
   "This is an onboarding and reading-path document, not a C4 architecture document and not a full design document.\n"
   "Focus on concrete source layout, important files, entry points, reading order, and high-signal versus low-signal areas.\n"
   "Infer from actual source files, tests, README files, package metadata, scripts, and configuration.\n"
   "Do not invent modules, workflows, or dependencies that are not supported by code or documentation.\n"
   "Mark uncertainty explicitly when a file or directory purpose is inferred rather than documented.\n"
   "Prefer practical guidance over abstract architecture theory.\n"
   "Keep the document concise enough to be reused in future AI coding prompts.\n"
   "When referencing any code file, folder, module, function, variable, or type, you MUST provide a relative Org-mode link in the format [[file:../../path/to/file::symbol_or_line][description_text]] pointing to its definition in the codebase (relative to the .ai.code.files/architecture/ output directory).\n"
   "Use text and tables as the main format. Include at most two small PlantUML diagrams only when they improve navigation: one top-level dependency or module graph, and optionally one suggested reading-path graph.\n"
   "Use Org Babel PlantUML blocks with :file when adding diagrams.\n"
   (format "Repository root: %s\n" git-root)
   (format "Create or update the Org file at %s.\n\n"
           ai-code-repo-map-output-relative-path)
   "Use this Org structure:\n"
   "#+TITLE: Repository Map\n\n"
   "* Purpose\n"
   "Explain that this document helps readers navigate a new repository quickly, and that it should be reviewed by humans.\n"
   "* What This Repository Does\n"
   "Summarize the repository responsibilities in 2-5 practical bullets.\n"
   "* Top-Level Directory and File Map\n"
   "Provide a table with Path, Purpose, Importance, and First-read? columns.\n"
   "* Suggested Reading Order\n"
   "Give a short ordered reading path for a new contributor. Explain why each step appears in that order.\n"
   "* Important Entry Points\n"
   "List interactive commands, public APIs, executable scripts, package entry files, hooks, or configuration entry points.\n"
   "* Core Concepts\n"
   "Define repository-specific concepts that a reader must know before editing code.\n"
   "* Module / File Relationship Sketch\n"
   "Include a compact PlantUML dependency sketch only if the relationships are supported by source evidence. Keep it small.\n"
   "* Files Usually Changed Together\n"
   "List files, tests, docs, or configs that appear coupled and should be considered together.\n"
   "* High-Risk or High-Churn Areas\n"
   "Identify files or directories that appear central, risky, unstable, or dependency-heavy. Explain the evidence.\n"
   "* Low-Signal Areas to Ignore Initially\n"
   "Identify generated, vendor, build-output, archived, or repetitive files that a new reader should skip at first.\n"
   "* Common Change Scenarios\n"
   "Map likely user tasks to the files or directories they should inspect first.\n"
   "* Open Questions\n"
   "List areas that need human confirmation.\n"
   "* Source Evidence\n"
   "Provide a table mapping important claims to Org links pointing at source evidence."))

;;;###autoload
(defun ai-code-derive-repo-map ()
  "Ask AI to derive a repository map document for the current repo.
The target Org file under `.ai.code.files/architecture/' is created if it does
not already exist, so the backend has a concrete document to create or update."
  (interactive)
  (let* ((git-root (or (ai-code--git-root)
                       (user-error "Not inside a Git repository"))))
    (ai-code-repo-map--ensure-document-file)
    (let* ((base-prompt
            (concat (ai-code-repo-map--derive-prompt git-root)
                    (or (ai-code--format-repo-context-info) "")))
           (initial-prompt (ai-code-repo-map--append-document-language base-prompt))
           (final-prompt (ai-code-plain-read-string "Derive repository map prompt: "
                                                    initial-prompt)))
      (when final-prompt
        (ai-code--insert-prompt final-prompt)))))

(provide 'ai-code-doc-repo-map)
;;; ai-code-doc-repo-map.el ends here
