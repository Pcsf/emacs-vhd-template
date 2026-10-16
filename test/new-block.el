;;; new-block.el --- Create a two-process block in a directory  -*- lexical-binding: t; -*-

;; Usage: emacs -Q --batch -L . -l test/new-block.el DIR NAME
;; Every prompt is answered with its default, as a user pressing RET would.

(require 'vhdl-tpl)

(let ((dir (nth 0 command-line-args-left))
      (name (nth 1 command-line-args-left))
      (vhdl-tpl-author "Test Author")
      (vhdl-tpl-read-function (lambda (_var default) default)))
  (setq command-line-args-left nil)
  (vhdl-tpl-new-block name dir))

;;; new-block.el ends here
