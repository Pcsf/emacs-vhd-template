;;; vhdl-tpl.el --- VHDL / FPGA file templates and snippets  -*- lexical-binding: t; -*-

;; Version: 0.1.0
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
;; Template syntax (everything else is copied verbatim):
;;
;;   {{name}}          ask for NAME once, reuse it everywhere
;;   {{name|default}}  same, with a default (RET accepts it);
;;                     `$file' `$stem' `$author' ... and earlier answers
;;                     may be used inside the default
;;   {{_}}             where point ends up after insertion
;;   {{>header.vhd}}   include partials/header.vhd
;;   {{!description}}  a comment line: shown while completing, never inserted
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

(defvar vhdl-tpl-mode-map (make-sparse-keymap)
  "Keymap of `vhdl-tpl-mode'.")

(defvar vhdl-tpl-command-map (make-sparse-keymap)
  "Commands reachable after `vhdl-tpl-key-prefix'.")

(defun vhdl-tpl--set-prefix (symbol value)
  "Set SYMBOL to VALUE and (re)bind `vhdl-tpl-command-map' to it."
  (when-let ((old (and (default-boundp symbol) (default-value symbol))))
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
  (read-string (if default
                   (format "%s (default %s): " var default)
                 (format "%s: " var))
               nil nil default))

(defun vhdl-tpl--builtins (file)
  "Alist of built-in variables for a buffer visiting FILE (may be nil)."
  (let* ((name (if file (file-name-nondirectory file) "my_module.vhd"))
         (base (file-name-sans-extension name))
         (stem (replace-regexp-in-string
                "\\(?:\\`tb_\\|_\\(?:tb\\|pkg\\|top\\)\\'\\)" "" base)))
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
  "Remove all `{{!...}}' comment lines from TEXT."
  (replace-regexp-in-string vhdl-tpl--comment-regexp "" text t t))

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
  (let* ((expanded (vhdl-tpl--strip-comments (vhdl-tpl--include-partials text)))
         (known (append values (vhdl-tpl--builtins file)))
         (vars nil))
    ;; Scan the template proper before its partials, so that the questions
    ;; about the entity come before the ones about the file header.
    (dolist (source (list text expanded))
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
      (let ((default (and (cdr cell)
                          (vhdl-tpl--expand-default (cdr cell) known))))
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
Non-nil INDENT re-indents the inserted lines according to the major mode."
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

(defun vhdl-tpl--complete (kind prompt &optional default)
  "Read the name of a KIND entry with PROMPT, proposing DEFAULT."
  (let* ((entries (vhdl-tpl--list kind))
         (descriptions (mapcar (lambda (e)
                                 (cons (car e) (vhdl-tpl--description (cdr e))))
                               entries))
         (completion-extra-properties
          (list :annotation-function
                (lambda (name)
                  (when-let ((text (cdr (assoc name descriptions))))
                    (concat "  " text)))))
         (completion-ignore-case t))
    (completing-read (if default
                         (format "%s(default %s) " prompt default)
                       prompt)
                     (mapcar #'car entries) nil t nil 'vhdl-tpl-history default)))

;;;###autoload
(defun vhdl-tpl-insert-template (name)
  "Insert the file template NAME at point."
  (interactive (list (vhdl-tpl--complete 'templates "Template: ")))
  (vhdl-tpl-insert 'templates name))

;;;###autoload
(defun vhdl-tpl-insert-snippet (name)
  "Insert the snippet NAME at point, indented for the current context."
  (interactive (list (vhdl-tpl--complete 'snippets "Snippet: ")))
  (vhdl-tpl-insert 'snippets name))

;;;###autoload
(defun vhdl-tpl-new-file (template file)
  "Create FILE and fill it with TEMPLATE."
  (interactive
   (let* ((template (vhdl-tpl--complete 'templates "New file from template: "))
          (ext (file-name-extension
                (vhdl-tpl--file 'templates template))))
     (list template
           (let ((file (read-file-name (format "New file (.%s): " ext))))
             (if (file-name-extension file) file (concat file "." ext))))))
  (let ((vhdl-tpl--inhibit-auto-insert t))
    (find-file file))
  (when (and (> (buffer-size) 0)
             (not (yes-or-no-p "Buffer is not empty; insert at point anyway? ")))
    (user-error "Aborted"))
  (vhdl-tpl-insert 'templates template))

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
        (let ((name (vhdl-tpl--complete 'templates "VHDL template: "
                                        (vhdl-tpl--suggest))))
          (unless (string-empty-p name)
            (vhdl-tpl-insert 'templates name)))
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

(when vhdl-tpl-key-prefix
  (define-key vhdl-tpl-mode-map (kbd vhdl-tpl-key-prefix) vhdl-tpl-command-map))

;;;###autoload
(defun vhdl-tpl-setup ()
  "Hook the templates into Emacs.
New .vhd/.vhdl files (and .xdc/.sdc files, see
`vhdl-tpl-constraint-templates') get a template through `auto-insert', and
`vhdl-tpl-mode' is enabled in VHDL buffers."
  (interactive)
  (define-auto-insert '("\\.vhdl?\\'" . "VHDL template") #'vhdl-tpl-auto-insert)
  (when vhdl-tpl-constraint-templates
    (define-auto-insert '("\\.xdc\\'" . "XDC template")
      #'vhdl-tpl-auto-insert-xdc)
    (define-auto-insert '("\\.sdc\\'" . "SDC template")
      #'vhdl-tpl-auto-insert-sdc))
  (auto-insert-mode 1)
  (add-hook 'vhdl-mode-hook #'vhdl-tpl-mode)
  (add-hook 'vhdl-ts-mode-hook #'vhdl-tpl-mode))

(provide 'vhdl-tpl)

;;; vhdl-tpl.el ends here
