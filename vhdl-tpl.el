;;; vhdl-tpl.el --- VHDL / FPGA file templates and snippets  -*- lexical-binding: t; -*-

;; Version: 0.2.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: vhdl, fpga, tools, convenience
;; URL: https://github.com/pcsf/emacs-vhd-template

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A tiny template engine for VHDL and FPGA projects that needs nothing
;; but Emacs itself (`auto-insert', `completing-read', `vhdl-mode').
;;
;; Templates are plain text files, so they can be edited (and even
;; compiled) without knowing any Elisp:
;;
;;   templates/  whole files: entity, testbench, package, FIFO, XDC, ...
;;   snippets/   fragments inserted at point: process, case, instance, ...
;;   partials/   shared pieces, e.g. the file header
;;
;; `vhdl-tpl-new-block' writes a test-first two-process block and
;; `vhdl-tpl-new-docs' the Org documents of a block.
;;
;; Template syntax (everything else is copied verbatim):
;;
;;   {{name}}          ask for NAME once, reuse it everywhere
;;   {{name|default}}  same, with a default (RET accepts it);
;;                     `$file' `$stem' `$author' ... and earlier answers
;;                     may be used inside the default
;;   {{_}}             where point ends up after insertion
;;   {{>header.vhd}}   include partials/header.vhd
;;   {{!description}}  a comment line: shown while completing, never inserted
;;   {{?name: text}}   a line giving the question to ask for NAME
;;   {{+other}}        a line naming a template this one needs next to it
;;
;; Built-in variables: filename, file, stem, date, year, author, email.
;;
;; Quick start:
;;
;;   (add-to-list 'load-path "/path/to/emacs-vhd-template")
;;   (require 'vhdl-tpl)
;;   (vhdl-tpl-setup)
;;
;; See README.md for details.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'autoinsert)
(require 'seq)

(declare-function org-table-map-tables "org-table" (function &optional quietly))
(declare-function org-table-align "org-table" ())
(declare-function org-update-dblock "org" ())

(defgroup vhdl-tpl nil
  "VHDL and FPGA file templates."
  :group 'tools
  :prefix "vhdl-tpl-")

(defconst vhdl-tpl--root
  (file-name-directory (or load-file-name buffer-file-name default-directory))
  "Directory holding the bundled templates, snippets and partials.")

(defcustom vhdl-tpl-user-directory nil
  "Directory with your own templates, or nil.
It uses the same layout as the package: `templates/', `snippets/' and
`partials/' sub-directories.  Files found here win over bundled ones with
the same name, so this is how you override the header or a template."
  :type '(choice (const :tag "None" nil) directory))

(defcustom vhdl-tpl-author nil
  "Value of the `author' variable.  Nil means the variable `user-full-name'."
  :type '(choice (const :tag "user-full-name" nil) string))

(defcustom vhdl-tpl-date-format "%Y-%m-%d"
  "Format string (see `format-time-string') for the `date' variable."
  :type 'string)

(defcustom vhdl-tpl-default-template "entity_arch"
  "Template proposed for a new VHDL file that has no more specific match."
  :type 'string)

(defcustom vhdl-tpl-constraint-templates t
  "Non-nil means also insert templates into new .xdc and .sdc files."
  :type 'boolean)

(defconst vhdl-tpl-doc-kinds
  '("test_report" "icd" "srs" "hdd" "vplan" "rtm" "adr" "review" "release")
  "Document kinds: BLOCK_KIND.org is filled from the template doc_KIND.")

(defcustom vhdl-tpl-doc-set '("icd" "srs" "hdd" "vplan" "rtm")
  "The documents `vhdl-tpl-new-docs' writes for a block.
Each is one of `vhdl-tpl-doc-kinds'."
  :type '(repeat string))

(defvar vhdl-tpl-mode-map (make-sparse-keymap)
  "Keymap of `vhdl-tpl-mode'.")

(defvar vhdl-tpl-command-map (make-sparse-keymap)
  "Commands reachable after `vhdl-tpl-key-prefix'.")

(defun vhdl-tpl--set-prefix (symbol value)
  "Set SYMBOL to VALUE and (re)bind `vhdl-tpl-command-map' to it."
  (when-let* ((old (and (default-boundp symbol) (default-value symbol))))
    (define-key vhdl-tpl-mode-map (kbd old) nil))
  (set-default symbol value)
  (when value
    (define-key vhdl-tpl-mode-map (kbd value) vhdl-tpl-command-map)))

(defcustom vhdl-tpl-key-prefix "C-c t"
  "Key sequence, in `kbd' syntax, that opens `vhdl-tpl-command-map'.
Nil means no binding."
  :type '(choice (const :tag "No binding" nil) string)
  :set #'vhdl-tpl--set-prefix)

(defvar vhdl-tpl-read-function #'vhdl-tpl--read
  "Function called with (VARIABLE DEFAULT) to get a variable's value.
Bind it to `(lambda (_var default) default)' to expand without prompting.")

(defvar vhdl-tpl-confirm-function #'y-or-n-p
  "Function called with a question; non-nil means yes.")

(defvar vhdl-tpl--labels nil
  "Alist of (VARIABLE . QUESTION) of the template being rendered.")

(defvar vhdl-tpl-history nil
  "Minibuffer history for template names.")

(defvar vhdl-tpl--inhibit-auto-insert nil
  "Non-nil while a command creates a file and inserts the template itself.")

(defconst vhdl-tpl--var-regexp
  "{{\\([[:alpha:]_][[:alnum:]_]*\\)\\(?:|\\([^}\n]*\\)\\)?}}"
  "Match a variable: group 1 is the name, group 2 the optional default.")

(defconst vhdl-tpl--partial-regexp "{{>\\([^}\n]+\\)}}"
  "Match a partial include: group 1 is the file name.")

(defconst vhdl-tpl--comment-regexp "^{{!\\([^}\n]*\\)}}\n?"
  "Match a comment line: group 1 is the text.")

(defconst vhdl-tpl--label-regexp
  "^{{\\?\\([[:alpha:]_][[:alnum:]_]*\\):[ \t]*\\([^}\n]*\\)}}\n?"
  "Match a question line: group 1 is the variable, group 2 the question.")

(defconst vhdl-tpl--requires-regexp "^{{\\+\\([^}\n]+\\)}}\n?"
  "Match a line naming needed templates: group 1 holds the names.")

(defconst vhdl-tpl--doc-regexp
  (concat "_" (regexp-opt vhdl-tpl-doc-kinds t) "\\(?:_[0-9]+\\)?\\'")
  "Match the document suffix of a file name without extension.")

(defconst vhdl-tpl--answers-file ".vhdl-tpl"
  "File next to the documents that keeps the answers given for each block.")

(defconst vhdl-tpl--cursor (string ?\uE000)
  "Private-use character marking where point should end up.")

;;;; Locating files

(defun vhdl-tpl--dirs (kind)
  "Existing directories for KIND (a string), user directory first."
  (cl-remove-if-not
   #'file-directory-p
   (mapcar (lambda (root) (expand-file-name kind root))
           (delq nil (list vhdl-tpl-user-directory vhdl-tpl--root)))))

(defun vhdl-tpl--list (kind)
  "Alist of (NAME . FILE) for KIND, `templates' or `snippets'.
NAME is the file name without extension; user files shadow bundled ones."
  (let (result)
    (dolist (dir (vhdl-tpl--dirs (symbol-name kind)))
      (dolist (file (directory-files dir t "\\`[^.#]"))
        (when (and (file-regular-p file) (not (string-suffix-p "~" file)))
          (let ((name (file-name-sans-extension (file-name-nondirectory file))))
            (unless (assoc name result)
              (push (cons name file) result))))))
    (sort result (lambda (a b) (string< (car a) (car b))))))

(defun vhdl-tpl--file (kind name)
  "Return the file of template NAME of KIND, or signal a `user-error'."
  (or (cdr (assoc name (vhdl-tpl--list kind)))
      (user-error "No %s named `%s'" (substring (symbol-name kind) 0 -1) name)))

(defun vhdl-tpl--read-file (file)
  "Return the contents of FILE as a string."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents file))
    (buffer-string)))

(defun vhdl-tpl--description (file)
  "Return the `{{!...}}' description of FILE, or nil."
  (let ((text (vhdl-tpl--read-file file)))
    (when (string-match vhdl-tpl--comment-regexp text)
      (string-trim (match-string 1 text)))))

;;;; Expansion

(defun vhdl-tpl--read (var default)
  "Ask for the value of VAR, proposing DEFAULT."
  (let ((question (or (cdr (assoc var vhdl-tpl--labels)) var)))
    (read-string (if default
                     (format "%s (default %s): " question default)
                   (format "%s: " question))
                 nil nil default)))

(defun vhdl-tpl--builtins (file)
  "Alist of built-in variables for a buffer visiting FILE (may be nil)."
  (let* ((name (if file (file-name-nondirectory file) "my_module.vhd"))
         (base (file-name-sans-extension name))
         (stem (replace-regexp-in-string
                (if (string-suffix-p ".org" name)
                    vhdl-tpl--doc-regexp
                  "\\(?:\\`tb_\\|_\\(?:tb\\|pkg\\|top\\)\\'\\)")
                "" base)))
    `(("filename" . ,name)
      ("file"     . ,base)
      ("stem"     . ,stem)
      ("date"     . ,(format-time-string vhdl-tpl-date-format))
      ("year"     . ,(format-time-string "%Y"))
      ("author"   . ,(or vhdl-tpl-author (user-full-name)))
      ("email"    . ,user-mail-address))))

(defun vhdl-tpl--include-partials (text)
  "Replace every `{{>file}}' in TEXT by the contents of that partial."
  (let ((depth 0))
    (while (string-match vhdl-tpl--partial-regexp text)
      (when (> (cl-incf depth) 8)
        (error "Partials nested too deeply (recursive include?)"))
      (let* ((beg (match-beginning 0))
             (end (match-end 0))
             (name (match-string 1 text))
             (file (cl-some (lambda (dir)
                              (let ((f (expand-file-name name dir)))
                                (and (file-regular-p f) f)))
                            (vhdl-tpl--dirs "partials")))
             (body (if file
                       (string-trim-right (vhdl-tpl--read-file file) "\n+")
                     (user-error "No partial named `%s'" name))))
        (setq text (concat (substring text 0 beg) body (substring text end)))))
    text))

(defun vhdl-tpl--strip-comments (text)
  "Remove the comment, question and needed-template lines from TEXT."
  (dolist (regexp (list vhdl-tpl--comment-regexp vhdl-tpl--label-regexp
                        vhdl-tpl--requires-regexp)
                  text)
    (setq text (replace-regexp-in-string regexp "" text t t))))

(defun vhdl-tpl--labels-in (text)
  "Alist of (VARIABLE . QUESTION) from the question lines of TEXT."
  (let ((pos 0) labels)
    (while (string-match vhdl-tpl--label-regexp text pos)
      (setq pos (match-end 0))
      (push (cons (match-string 1 text) (string-trim (match-string 2 text)))
            labels))
    (nreverse labels)))

(defun vhdl-tpl--requires (name)
  "Names of the templates the template NAME needs next to it."
  (let ((text (vhdl-tpl--read-file (vhdl-tpl--file 'templates name)))
        (pos 0) names)
    (while (string-match vhdl-tpl--requires-regexp text pos)
      (setq pos (match-end 0))
      (setq names (append names (split-string (match-string 1 text)))))
    names))

;;;; Answers kept per block

(defun vhdl-tpl--read-answers (dir)
  "The alist (BLOCK . ANSWERS) kept in directory DIR, or nil."
  (let ((file (expand-file-name vhdl-tpl--answers-file dir)))
    (when (file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (ignore-errors (read (current-buffer)))))))

(defun vhdl-tpl--stored-answers (file)
  "Answers kept for the block that the document FILE belongs to."
  (when (and file (string-suffix-p ".org" file))
    (cdr (assoc (cdr (assoc "stem" (vhdl-tpl--builtins file)))
                (vhdl-tpl--read-answers (file-name-directory file))))))

(defun vhdl-tpl--store-answers (dir block answers)
  "Keep ANSWERS, an alist, for BLOCK in directory DIR."
  (let ((all (assoc-delete-all block (vhdl-tpl--read-answers dir))))
    (with-temp-file (expand-file-name vhdl-tpl--answers-file dir)
      (insert ";; Answers given for each block's documents; they are proposed\n"
              ";; again when another document of the same block is created.\n")
      (let ((print-length nil) (print-level nil))
        (pp (sort (cons (cons block answers) all)
                  (lambda (a b) (string< (car a) (car b))))
            (current-buffer))))))

(defun vhdl-tpl--expand-default (default known)
  "Replace `$name' in DEFAULT by its value in the alist KNOWN."
  (replace-regexp-in-string
   "\\$\\([[:alpha:]_][[:alnum:]_]*\\)"
   (lambda (match) (or (cdr (assoc (substring match 1) known)) match))
   default t t))

(defun vhdl-tpl-render (text &optional values file)
  "Expand template TEXT and return the resulting string.
VALUES is an alist of (VARIABLE . VALUE) that are used without asking.
FILE is the file name the built-in variables refer to.  Other variables
are requested through `vhdl-tpl-read-function'.  The cursor position is
marked by `vhdl-tpl--cursor' in the result."
  (let* ((included (vhdl-tpl--include-partials text))
         (expanded (vhdl-tpl--strip-comments included))
         (vhdl-tpl--labels (vhdl-tpl--labels-in included))
         (stored (vhdl-tpl--stored-answers file))
         (known (append values (vhdl-tpl--builtins file)))
         (vars nil))
    ;; Scan the template proper before its partials, so that the questions
    ;; about the entity come before the ones about the file header.
    (dolist (source (list (vhdl-tpl--strip-comments text) expanded))
      (let ((pos 0))
        (while (string-match vhdl-tpl--var-regexp source pos)
          (let ((var (match-string 1 source))
                (default (match-string 2 source)))
            (setq pos (match-end 0))
            (unless (or (string= var "_") (assoc var known))
              (let ((cell (assoc var vars)))
                (cond ((null cell) (push (cons var default) vars))
                      ((and default (null (cdr cell)))
                       (setcdr cell default)))))))))
    (dolist (cell (nreverse vars))
      (let ((default (or (cdr (assoc (car cell) stored))
                         (and (cdr cell)
                              (vhdl-tpl--expand-default (cdr cell) known)))))
        (push (cons (car cell) (funcall vhdl-tpl-read-function
                                        (car cell) default))
              known)))
    (replace-regexp-in-string
     vhdl-tpl--var-regexp
     (lambda (match)
       (string-match vhdl-tpl--var-regexp match)
       (let ((var (match-string 1 match)))
         (if (string= var "_")
             vhdl-tpl--cursor
           (or (cdr (assoc var known)) ""))))
     expanded t t)))

;;;; Insertion

(defun vhdl-tpl--insert-string (string &optional indent)
  "Insert STRING at point and move point to its cursor marker.
Non-nil INDENT re-indents the inserted lines according to the major mode.
In an Org buffer the inserted tables are re-aligned, since the answers
rarely have the width of the markers they replace."
  (let ((start (point-marker))
        (cursor nil))
    (insert string)
    (let ((end (point-marker)))
      (goto-char start)
      (when (search-forward vhdl-tpl--cursor end t)
        (delete-char -1)
        (setq cursor (point-marker)))
      (while (search-forward vhdl-tpl--cursor end t)
        (delete-char -1))
      (when (and indent (derived-mode-p 'vhdl-mode 'vhdl-ts-mode))
        (indent-region (save-excursion
                         (goto-char start)
                         (line-beginning-position))
                       end))
      (when (derived-mode-p 'org-mode)
        (save-restriction
          (narrow-to-region start end)
          (vhdl-tpl--update-dblocks)
          (org-table-map-tables #'org-table-align t)))
      (goto-char (or cursor end))
      (when (and cursor indent
                 (save-excursion (beginning-of-line) (looking-at "[ \t]*$")))
        (indent-according-to-mode)
        (end-of-line))
      (set-marker start nil)
      (set-marker end nil)
      (when cursor (set-marker cursor nil)))))

;;;###autoload
(defun vhdl-tpl-insert (kind name &optional values)
  "Insert the template or snippet NAME of KIND at point.
KIND is `templates' or `snippets'.  VALUES is an alist of predefined
variables, see `vhdl-tpl-render'."
  (let* ((text (vhdl-tpl--read-file (vhdl-tpl--file kind name)))
         (snippet (eq kind 'snippets))
         (string (vhdl-tpl-render (if snippet (string-trim-right text "\n+") text)
                                  values buffer-file-name)))
    (vhdl-tpl--insert-string string snippet)))

(defun vhdl-tpl--group (name file)
  "Heading under which the chooser lists the template NAME stored in FILE."
  (let ((ext (downcase (or (file-name-extension file) ""))))
    (cond ((equal ext "org") "Documents")
          ((not (member ext '("vhd" "vhdl"))) "Project files")
          ((string-match-p "\\`\\(?:bfm_\\|tb_\\|sb_\\|testbench\\)\\|_tb\\'" name)
           "Verification")
          (t "Design"))))

(defun vhdl-tpl--same-type-p (ext file)
  "Non-nil if FILE has the extension EXT; .vhd and .vhdl are one type."
  (let ((norm (lambda (e) (if (equal e "vhdl") "vhd" (downcase (or e ""))))))
    (equal (funcall norm ext) (funcall norm (file-name-extension file)))))

(defun vhdl-tpl--complete (kind prompt &optional default ext)
  "Read the name of a KIND entry with PROMPT, proposing DEFAULT.
With EXT, a file extension, offer only the entries of that file type,
unless there are none."
  (let* ((all (vhdl-tpl--list kind))
         (entries (or (and ext (cl-remove-if-not
                                (lambda (e) (vhdl-tpl--same-type-p ext (cdr e)))
                                all))
                      all))
         (descriptions (mapcar (lambda (e)
                                 (cons (car e) (vhdl-tpl--description (cdr e))))
                               entries))
         (annotate (lambda (name)
                     (when-let* ((text (cdr (assoc name descriptions))))
                       (concat "  " text))))
         (group (lambda (name transform)
                  (if transform
                      name
                    (vhdl-tpl--group name (cdr (assoc name entries))))))
         (names (mapcar #'car entries))
         (table (lambda (string pred action)
                  (if (eq action 'metadata)
                      `(metadata (annotation-function . ,annotate)
                                 (group-function . ,group))
                    (complete-with-action action names string pred))))
         (completion-ignore-case t))
    (completing-read (if default
                         (format "%s(default %s) " prompt default)
                       prompt)
                     table nil t nil 'vhdl-tpl-history default)))

(defun vhdl-tpl--buffer-type (all)
  "Extension of the visited file, or nil when ALL is non-nil."
  (and (not all) buffer-file-name (file-name-extension buffer-file-name)))

;;;###autoload
(defun vhdl-tpl-insert-template (name)
  "Insert the file template NAME at point.
Only the templates of the buffer's file type are offered; with a prefix
argument, all of them."
  (interactive (list (vhdl-tpl--complete
                      'templates "Template: " nil
                      (vhdl-tpl--buffer-type current-prefix-arg))))
  (vhdl-tpl-insert 'templates name))

;;;###autoload
(defun vhdl-tpl-insert-snippet (name)
  "Insert the snippet NAME at point, indented for the current context.
Only the snippets of the buffer's file type are offered; with a prefix
argument, all of them."
  (interactive (list (vhdl-tpl--complete
                      'snippets "Snippet: " nil
                      (vhdl-tpl--buffer-type current-prefix-arg))))
  (vhdl-tpl-insert 'snippets name))

;;;###autoload
(defun vhdl-tpl-new-file (template file)
  "Create FILE and fill it with TEMPLATE."
  (interactive
   (let* ((template (vhdl-tpl--complete 'templates "New file from template: "))
          (ext (file-name-extension
                (vhdl-tpl--file 'templates template))))
     (list template
           (let ((file (read-file-name
                        (if ext (format "New file (.%s): " ext) "New file: "))))
             ;; Templates without extension (Makefile) keep the name as typed.
             (if (or (null ext) (file-name-extension file))
                 file
               (concat file "." ext))))))
  (let ((vhdl-tpl--inhibit-auto-insert t))
    (find-file file))
  (when (and (> (buffer-size) 0)
             (not (yes-or-no-p "Buffer is not empty; insert at point anyway? ")))
    (user-error "Aborted"))
  (vhdl-tpl-insert 'templates template)
  (vhdl-tpl--offer-requirements template))

;;;; A new two-process block, test first

(defconst vhdl-tpl-mk-repository
  "https://github.com/Pcsf/makefile_project_template.git"
  "The mk/ build framework a new block's project.mk is written for.")

(defun vhdl-tpl--project-root (dir)
  "Nearest directory at or above DIR with a project.mk or .git, else DIR."
  (or (locate-dominating-file
       dir (lambda (d) (or (file-exists-p (expand-file-name "project.mk" d))
                           (file-exists-p (expand-file-name ".git" d)))))
      dir))

(defun vhdl-tpl--write (template file values)
  "Render TEMPLATE with VALUES into the new FILE."
  (make-directory (file-name-directory file) t)
  (let ((text (vhdl-tpl-render
               (vhdl-tpl--read-file (vhdl-tpl--file 'templates template))
               values file)))
    (with-temp-file file
      (insert (replace-regexp-in-string
               (regexp-quote vhdl-tpl--cursor) "" text t t))))
  (when (string-suffix-p ".org" file)
    (vhdl-tpl--finish-org file)))

(defun vhdl-tpl--update-dblocks ()
  "Update the dynamic blocks of the Org buffer; one that fails stays as it is.
A block may read another document; a file visited only for that is closed
again, so that it is read afresh the next time."
  (let ((before (buffer-list)))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "^[ \t]*#\\+BEGIN:" nil t)
        (condition-case err
            (save-excursion (beginning-of-line) (org-update-dblock))
          (error (message "vhdl-tpl: block not updated: %s"
                          (error-message-string err))))
        (forward-line 1)))
    (dolist (buffer (buffer-list))
      (unless (or (memq buffer before) (buffer-modified-p buffer)
                  (not (buffer-file-name buffer)))
        (kill-buffer buffer)))))

(defun vhdl-tpl--finish-org (file)
  "Fill the dynamic blocks of the Org document FILE and align its tables."
  (require 'org)
  (with-temp-buffer
    (insert-file-contents file)
    (setq default-directory (file-name-directory (expand-file-name file)))
    (delay-mode-hooks (org-mode))
    (vhdl-tpl--update-dblocks)
    (org-table-map-tables #'org-table-align t)
    (write-region nil nil file nil 'silent))
  (when-let* ((buffer (find-buffer-visiting file)))
    (unless (buffer-modified-p buffer)
      (with-current-buffer buffer (revert-buffer t t t)))))

(defun vhdl-tpl--offer-requirements (template)
  "Offer to create the templates TEMPLATE needs next to the visited file.
Only the missing ones are named, and they are written with their default
answers."
  (when buffer-file-name
    (let* ((dir (file-name-directory buffer-file-name))
           (seen (list template))
           (queue (vhdl-tpl--requires template))
           missing)
      (while queue
        (let ((name (pop queue)))
          (unless (member name seen)
            (push name seen)
            (setq queue (append queue (vhdl-tpl--requires name)))
            (let* ((source (vhdl-tpl--file 'templates name))
                   (target (expand-file-name
                            (file-name-nondirectory source) dir)))
              (unless (file-exists-p target)
                (push (cons name target) missing))))))
      (setq missing (nreverse missing))
      (when (and missing
                 (funcall vhdl-tpl-confirm-function
                          (format "Also create %s here? "
                                  (mapconcat (lambda (m)
                                               (file-name-nondirectory (cdr m)))
                                             missing ", "))))
        (let ((vhdl-tpl-read-function (lambda (_var default) (or default ""))))
          (dolist (m missing)
            (vhdl-tpl--write (car m) (cdr m) nil)))))))

;;;; Port table from an entity

(defun vhdl-tpl--type-width (type)
  "Width of the VHDL TYPE as a string: a number, a generic, or TYPE itself."
  (let ((case-fold-search t))
    (cond ((string-match-p "\\`\\(?:std_u?logic\\|bit\\|boolean\\)\\'" type) "1")
          ((string-match "(\\s-*\\([0-9]+\\)\\s-+downto\\s-+0\\s-*)\\'" type)
           (number-to-string (1+ (string-to-number (match-string 1 type)))))
          ((string-match
            "(\\s-*\\([[:alnum:]_]+\\)\\s-*-\\s-*1\\s-+downto\\s-+0\\s-*)\\'" type)
           (match-string 1 type))
          (t type))))

(defun vhdl-tpl--declarations (beg end)
  "Parse `NAMES : [DIR] TYPE [:= INIT]; -- COMMENT' lines between BEG and END.
Return a list of (NAME DIR TYPE COMMENT); DIR is nil for a record field."
  (let ((case-fold-search t) result)
    (save-excursion
      (goto-char beg)
      (while (re-search-forward
              (concat "^[ \t]*\\([[:alnum:]_, \t]+?\\)[ \t]*:[ \t]*"
                      "\\(?:\\(in\\|out\\|inout\\|buffer\\)[ \t]+\\)?"
                      "\\([^;\n]*?\\)[ \t]*;?[ \t]*"
                      "\\(?:--[ \t]*\\(.*?\\)\\)?[ \t]*$")
              end t)
        (let ((names (match-string 1))
              (dir (match-string 2))
              (type (match-string 3))
              (comment (or (match-string 4) "")))
          (setq type (string-trim (replace-regexp-in-string
                                   "[ \t]*\\(?::=\\|--\\).*\\'" "" type)))
          (dolist (name (split-string names "[, \t]+" t))
            (push (list name (and dir (downcase dir)) type comment) result)))))
    (nreverse result)))

(defun vhdl-tpl--port-clause ()
  "Bounds (BEG . END) of the entity's port clause in the buffer, or nil."
  (let ((case-fold-search t))
    (save-excursion
      (goto-char (point-min))
      (when (and (re-search-forward "^[ \t]*entity[ \t]+[[:alnum:]_]+[ \t]+is\\_>" nil t)
                 (re-search-forward "\\_<port[ \t\n]*(" nil t))
        (let ((beg (point)) (depth 1))
          (while (and (> depth 0) (re-search-forward "--.*$\\|[()]" nil t))
            (pcase (char-after (match-beginning 0))
              (?\( (cl-incf depth))
              (?\) (cl-decf depth))))
          (and (= depth 0) (cons beg (1- (point)))))))))

(defun vhdl-tpl--records (file)
  "Alist (TYPE . FIELDS) of the record types declared in the VHDL FILE."
  (when (file-readable-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (let ((case-fold-search t) result)
        (while (re-search-forward
                "^[ \t]*type[ \t]+\\([[:alnum:]_]+\\)[ \t]+is[ \t]+record\\_>" nil t)
          (let ((name (downcase (match-string 1)))
                (beg (point)))
            (when (re-search-forward "^[ \t]*end[ \t]+record\\_>" nil t)
              (push (cons name (vhdl-tpl--declarations beg (match-beginning 0)))
                    result))))
        result))))

(defun vhdl-tpl--port-rows (file)
  "Rows (PORT DIR WIDTH DESCRIPTION) for the entity in the VHDL FILE.
A port of a record type declared in FILE or in its _pkg file is listed
field by field."
  (let* ((pkg (concat (file-name-sans-extension file) "_pkg."
                      (file-name-extension file)))
         (records (append (vhdl-tpl--records file) (vhdl-tpl--records pkg)))
         (ports (with-temp-buffer
                  (insert-file-contents file)
                  (when-let* ((bounds (vhdl-tpl--port-clause)))
                    (vhdl-tpl--declarations (car bounds) (cdr bounds)))))
         rows)
    (dolist (port ports)
      (pcase-let ((`(,name ,dir ,type ,comment) port))
        (if-let* ((fields (cdr (assoc (downcase type) records))))
            (dolist (field fields)
              (push (list (concat name "." (nth 0 field)) dir
                          (vhdl-tpl--type-width (nth 2 field)) (nth 3 field))
                    rows))
          (push (list name dir (vhdl-tpl--type-width type) comment) rows))))
    (nreverse rows)))

;;;###autoload
(defun org-dblock-write:vhdl-ports (params)
  "Write the port table of the entity in the VHDL file named by PARAMS.
PARAMS has :file, relative to the document.  Update the block with
\\[org-ctrl-c-ctrl-c] on its first line after the entity changed."
  (let* ((file (plist-get params :file))
         (rows (and file (file-readable-p file) (vhdl-tpl--port-rows file))))
    (unless rows
      (insert (format "# No entity read from %s yet: update this block when it exists.\n"
                      (or file "a :file"))))
    (insert "| Port | Dir | Width | Description |\n|-\n")
    (dolist (row (or rows '(("" "" "" ""))))
      (insert "| " (mapconcat #'identity row " | ") " |\n"))
    (delete-char -1)
    (org-table-align)))

(defun vhdl-tpl--add-test-case (project-mk tb)
  "Append TB to TESTS in PROJECT-MK unless the file already names it."
  (with-temp-buffer
    (insert-file-contents project-mk)
    (unless (re-search-forward (concat "\\_<" (regexp-quote tb) "\\_>") nil t)
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert (format "TESTS += %s\n" tb))
      (write-region nil nil project-mk)
      t)))

(defun vhdl-tpl--update-compile-order (dir first last)
  "Keep DIR/.compile_order listing the files FIRST before, and LAST after, the rest.
Both are lists of file names.  A name already in the file stays where it
is; the file is created when there is none.  The mk framework reads it
and never rewrites it."
  (let* ((file (expand-file-name ".compile_order" dir))
         (lines (if (file-exists-p file)
                    (with-temp-buffer
                      (insert-file-contents file)
                      (split-string (string-trim-right (buffer-string) "\n") "\n"))
                  (list (format "# VHDL compilation order for: %s"
                                (file-name-nondirectory (directory-file-name dir)))
                        "# A package or entity goes before the files that use it.")))
         (header (seq-take-while (lambda (l) (string-prefix-p "#" l)) lines))
         (rest (seq-drop lines (length header)))
         (present (lambda (name) (member name lines)))
         (new-first (cl-remove-if present first))
         (new-last (cl-remove-if present last)))
    (when (or new-first new-last (not (file-exists-p file)))
      (make-directory dir t)
      (with-temp-file file
        (insert (string-join (append header new-first rest new-last) "\n") "\n")))))

;;;###autoload
(defun vhdl-tpl-new-block (name root)
  "Create the two-process block NAME in project ROOT, ready for test-first work.
Writes src/NAME_pkg.vhd (port records), src/NAME.vhd (the two-process
skeleton with an empty comb process) and tb/tb_NAME.vhd (numbered test
cases on tb_util_pkg, which is written to tb/ when the project has none).
A project without project.mk also gets project.mk and a Makefile for the
mk/ build framework; an existing project.mk gets the testbench added to
TESTS.  The .compile_order of src/ and tb/ list the new files in the right
place.  Existing files are never overwritten.  As written, the testbench
fails on the skeleton: that is the RED step."
  (interactive
   (let ((root (read-directory-name
                "Project root: " (vhdl-tpl--project-root default-directory))))
     (list (read-string "Block name: ") root)))
  (when (string-empty-p name)
    (user-error "The block needs a name"))
  (let* ((root (file-name-as-directory (expand-file-name root)))
         (tb (concat "tb_" name))
         (files `(("two_process_pkg"      . ,(expand-file-name (format "src/%s_pkg.vhd" name) root))
                  ("two_process_skeleton" . ,(expand-file-name (format "src/%s.vhd" name) root))
                  ("two_process_tb"       . ,(expand-file-name (format "tb/%s.vhd" tb) root))))
         (project-mk (expand-file-name "project.mk" root))
         (makefile (expand-file-name "Makefile" root))
         (new-project (not (file-exists-p project-mk))))
    (when-let* ((taken (cl-remove-if-not #'file-exists-p (mapcar #'cdr files))))
      (user-error "Already exists: %s"
                  (mapconcat #'abbreviate-file-name taken ", ")))
    (let* ((iface (funcall vhdl-tpl-read-function "iface" name))
           (desc (funcall vhdl-tpl-read-function "desc" "TODO"))
           (values `(("entity" . ,name) ("iface" . ,iface) ("tb" . ,tb)
                     ("desc" . ,desc)
                     ("project" . ,(file-name-nondirectory
                                    (directory-file-name root))))))
      (dolist (f files)
        (vhdl-tpl--write (car f) (cdr f) values))
      (let ((util (expand-file-name "tb/tb_util_pkg.vhd" root)))
        (unless (file-exists-p util)
          (vhdl-tpl--write "tb_util_pkg" util values)))
      (vhdl-tpl--update-compile-order
       (expand-file-name "src" root) nil
       (list (format "%s_pkg.vhd" name) (format "%s.vhd" name)))
      (vhdl-tpl--update-compile-order
       (expand-file-name "tb" root) '("tb_util_pkg.vhd") (list (format "%s.vhd" tb)))
      (if new-project
          (vhdl-tpl--write "project_mk" project-mk values)
        (vhdl-tpl--add-test-case project-mk tb))
      (unless (file-exists-p makefile)
        (with-temp-file makefile
          (insert "include mk/Makefile\n"))))
    (let ((vhdl-tpl--inhibit-auto-insert t))
      (find-file (cdr (nth 2 files))))
    (message "%s"
             (if (file-directory-p (expand-file-name "mk" root))
                 "RED: make test TEST_CHECK=0 GHDL_TEST_FLAGS=--assert-level=failure   GREEN: make test"
               (format "No mk/ yet: git submodule add %s mk" vhdl-tpl-mk-repository)))))

;;;; The documents of a block

;;;###autoload
(defun vhdl-tpl-new-docs (name root)
  "Write the documents of block NAME into the doc/ directory of project ROOT.
The set is `vhdl-tpl-doc-set': doc/NAME_icd.org, doc/NAME_srs.org and so
on, linked to each other.  Each question is asked once for the whole set
and the answers are kept in doc/ for the block's later documents.
Existing files are never overwritten; the missing ones are added."
  (interactive
   (let ((root (read-directory-name
                "Project root: " (vhdl-tpl--project-root default-directory))))
     (list (read-string "Block name: "
                        (and buffer-file-name
                             (cdr (assoc "stem" (vhdl-tpl--builtins
                                                 buffer-file-name)))))
           root)))
  (when (string-empty-p name)
    (user-error "The block needs a name"))
  (let* ((dir (expand-file-name "doc/" (expand-file-name root)))
         (files (cl-remove-if
                 (lambda (f) (file-exists-p (cdr f)))
                 (mapcar (lambda (kind)
                           (cons (concat "doc_" kind)
                                 (expand-file-name
                                  (format "%s_%s.org" name kind) dir)))
                         vhdl-tpl-doc-set)))
         (answers nil)
         (ask vhdl-tpl-read-function)
         (vhdl-tpl-read-function
          (lambda (var default)
            (cdr (or (assoc var answers)
                     (car (push (cons var (funcall ask var default))
                                answers)))))))
    (unless files
      (user-error "The documents of %s already exist in %s"
                  name (abbreviate-file-name dir)))
    (make-directory dir t)
    (dolist (f files)
      (vhdl-tpl--write (car f) (cdr f) `(("module" . ,name))))
    (vhdl-tpl--store-answers
     dir name (append (reverse answers)
                      (cl-remove-if (lambda (a) (assoc (car a) answers))
                                    (cdr (assoc name (vhdl-tpl--read-answers
                                                      dir))))))
    ;; Once more, now that every document a block reads from exists.
    (dolist (f files)
      (vhdl-tpl--finish-org (cdr f)))
    (let ((vhdl-tpl--inhibit-auto-insert t))
      (find-file (cdr (car files))))
    (message "Wrote %s"
             (mapconcat (lambda (f) (file-name-nondirectory (cdr f)))
                        files ", "))))

;;;; Integration with auto-insert

(defun vhdl-tpl--suggest ()
  "Template to propose for the current buffer, judging by its file name."
  (let ((base (file-name-base (or buffer-file-name ""))))
    (cond ((or (string-suffix-p "_tb" base) (string-prefix-p "tb_" base))
           "testbench")
          ((string-suffix-p "_pkg" base) "package")
          ((string-suffix-p "_top" base) "top_level")
          (t vhdl-tpl-default-template))))

(defun vhdl-tpl-auto-insert ()
  "`auto-insert' action for VHDL files: ask which template to use."
  (unless vhdl-tpl--inhibit-auto-insert
    (condition-case nil
        (let ((name (vhdl-tpl--complete
                     'templates "VHDL template: " (vhdl-tpl--suggest)
                     (or (and buffer-file-name
                              (file-name-extension buffer-file-name))
                         "vhd"))))
          (unless (string-empty-p name)
            (vhdl-tpl-insert 'templates name)
            (vhdl-tpl--offer-requirements name)))
      (quit nil))))

(defun vhdl-tpl-auto-insert-xdc ()
  "`auto-insert' action for Xilinx constraint files."
  (unless vhdl-tpl--inhibit-auto-insert
    (vhdl-tpl-insert 'templates "xdc_constraints")))

(defun vhdl-tpl-auto-insert-sdc ()
  "`auto-insert' action for SDC constraint files."
  (unless vhdl-tpl--inhibit-auto-insert
    (vhdl-tpl-insert 'templates "sdc_constraints")))

;;;###autoload
(define-minor-mode vhdl-tpl-mode
  "Minor mode that provides the `vhdl-tpl-key-prefix' key bindings."
  :lighter " Tpl"
  :keymap vhdl-tpl-mode-map)

(define-key vhdl-tpl-command-map "t" #'vhdl-tpl-insert-template)
(define-key vhdl-tpl-command-map "s" #'vhdl-tpl-insert-snippet)
(define-key vhdl-tpl-command-map "n" #'vhdl-tpl-new-file)
(define-key vhdl-tpl-command-map "b" #'vhdl-tpl-new-block)
(define-key vhdl-tpl-command-map "d" #'vhdl-tpl-new-docs)

(when vhdl-tpl-key-prefix
  (define-key vhdl-tpl-mode-map (kbd vhdl-tpl-key-prefix) vhdl-tpl-command-map))

(defun vhdl-tpl--enable-in-document ()
  "Enable `vhdl-tpl-mode' in an Org file named as one of the documents."
  (when (and buffer-file-name
             (string-match-p vhdl-tpl--doc-regexp
                             (file-name-base buffer-file-name)))
    (vhdl-tpl-mode 1)))

;;;###autoload
(defun vhdl-tpl-setup ()
  "Hook the templates into Emacs.
New .vhd/.vhdl files (and .xdc/.sdc files, see
`vhdl-tpl-constraint-templates') get a template through `auto-insert', and
`vhdl-tpl-mode' is enabled in VHDL buffers and in the Org documents of a
block (files named BLOCK_icd.org, BLOCK_srs.org, ...)."
  (interactive)
  (define-auto-insert '("\\.vhdl?\\'" . "VHDL template") #'vhdl-tpl-auto-insert)
  (when vhdl-tpl-constraint-templates
    (define-auto-insert '("\\.xdc\\'" . "XDC template")
      #'vhdl-tpl-auto-insert-xdc)
    (define-auto-insert '("\\.sdc\\'" . "SDC template")
      #'vhdl-tpl-auto-insert-sdc))
  (auto-insert-mode 1)
  (add-hook 'vhdl-mode-hook #'vhdl-tpl-mode)
  (add-hook 'vhdl-ts-mode-hook #'vhdl-tpl-mode)
  (add-hook 'org-mode-hook #'vhdl-tpl--enable-in-document))

(provide 'vhdl-tpl)

;;; vhdl-tpl.el ends here
