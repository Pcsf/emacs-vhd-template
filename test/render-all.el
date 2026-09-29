;;; render-all.el --- Render every bundled template to build/rendered  -*- lexical-binding: t; -*-

;; Usage: emacs -Q --batch -L . -l test/render-all.el
;; Every prompt is answered with its default, so the defaults have to yield
;; compilable VHDL.  The file name each template is rendered under matters:
;; it feeds the `$file' and `$stem' defaults.

(require 'vhdl-tpl)

(defconst render-all--file-names
  '(("testbench"     . "entity_arch_tb.vhd")   ; tests the entity_arch template
    ("testbench_bfm" . "axis_skid_tb.vhd")     ; tests the axis_skid template
    ("package"       . "my_pkg.vhd")           ; `package' is a reserved word
    ("ghdl_makefile" . "Makefile")))

(let* ((out (expand-file-name "build/rendered"
                              (file-name-directory
                               (directory-file-name
                                (file-name-directory load-file-name)))))
       (vhdl-tpl-author "Test Author")
       (vhdl-tpl-read-function (lambda (_var default) default)))
  (make-directory out t)
  (dolist (entry (vhdl-tpl--list 'templates))
    (let* ((source (cdr entry))
           (name (or (cdr (assoc (car entry) render-all--file-names))
                     (file-name-nondirectory source)))
           (target (expand-file-name name out)))
      (with-temp-file target
        (insert (string-replace
                 vhdl-tpl--cursor ""
                 (vhdl-tpl-render (vhdl-tpl--read-file source) nil target))))
      (message "rendered %s" name))))

;;; render-all.el ends here
