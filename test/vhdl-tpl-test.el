;;; vhdl-tpl-test.el --- Tests for vhdl-tpl  -*- lexical-binding: t; -*-

;; Run with: emacs -Q --batch -L . -l test/vhdl-tpl-test.el \
;;             -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'vhdl-tpl)
(require 'vhdl-mode)

(defun vhdl-tpl-test--default (_var default) default)

(defmacro vhdl-tpl-test--with-defaults (&rest body)
  "Run BODY without prompting and with a fixed author."
  `(let ((vhdl-tpl-read-function #'vhdl-tpl-test--default)
         (vhdl-tpl-author "Test Author")
         (vhdl-tpl-user-directory nil))
     ,@body))

(defun vhdl-tpl-test--render (text &optional values file)
  (string-replace vhdl-tpl--cursor "|"
                  (vhdl-tpl-render text values file)))

;;;; Engine

(ert-deftest vhdl-tpl-test-variable-asked-once ()
  (let* ((asked nil)
         (vhdl-tpl-read-function
          (lambda (var default) (push var asked) (or default "x"))))
    (should (equal (vhdl-tpl-render "{{a}} {{a}} {{b|two}}")
                   "x x two"))
    (should (equal (nreverse asked) '("a" "b")))))

(ert-deftest vhdl-tpl-test-default-from-any-occurrence ()
  (vhdl-tpl-test--with-defaults
   (should (equal (vhdl-tpl-render "{{a}} {{a|first}}") "first first"))))

(ert-deftest vhdl-tpl-test-supplied-values-are-not-asked ()
  (let ((vhdl-tpl-read-function (lambda (&rest _) (error "Should not ask"))))
    (should (equal (vhdl-tpl-render "{{a|d}}" '(("a" . "given"))) "given"))))

(ert-deftest vhdl-tpl-test-builtins-and-dollar-defaults ()
  (vhdl-tpl-test--with-defaults
   (should (equal (vhdl-tpl-render "{{file}} {{stem}} {{filename}}" nil
                                   "/tmp/foo_tb.vhd")
                  "foo_tb foo foo_tb.vhd"))
   (should (equal (vhdl-tpl-render "{{e|$stem}}_x {{a|$author}}" nil
                                   "/tmp/tb_bar.vhd")
                  "bar_x Test Author"))
   (should (equal (vhdl-tpl-render "{{e|$stem}}" nil "/tmp/top_pkg.vhd") "top"))))

(ert-deftest vhdl-tpl-test-defaults-see-earlier-answers ()
  (let ((vhdl-tpl-read-function
         (lambda (var default) (if (equal var "a") "alpha" default))))
    (should (equal (vhdl-tpl-render "{{a}} {{b|$a-beta}}") "alpha alpha-beta"))))

(ert-deftest vhdl-tpl-test-values-are-not-reexpanded ()
  (should (equal (vhdl-tpl-render "{{a}}" '(("a" . "{{b}}"))) "{{b}}")))

(ert-deftest vhdl-tpl-test-single-braces-are-literal ()
  (vhdl-tpl-test--with-defaults
   (should (equal (vhdl-tpl-render "{ PACKAGE_PIN {{p|E3}} } {0 5}")
                  "{ PACKAGE_PIN E3 } {0 5}"))))

(ert-deftest vhdl-tpl-test-cursor-marker ()
  (vhdl-tpl-test--with-defaults
   (should (equal (vhdl-tpl-test--render "a{{_}}b") "a|b"))))

(ert-deftest vhdl-tpl-test-comments-are-removed-and-described ()
  (vhdl-tpl-test--with-defaults
   (should (equal (vhdl-tpl-render "{{!About this}}\nbody\n") "body\n"))))

(ert-deftest vhdl-tpl-test-partial-include ()
  (vhdl-tpl-test--with-defaults
   (let ((out (vhdl-tpl-render "{{>header.vhd}}\nbody" nil "/tmp/foo.vhd")))
     (should (string-match-p "^-- File +: foo.vhd$" out))
     (should (string-match-p "^-- Author +: Test Author$" out))
     (should (string-suffix-p "\nbody" out)))))

(ert-deftest vhdl-tpl-test-missing-partial-is-an-error ()
  (should-error (vhdl-tpl-render "{{>nope.vhd}}") :type 'user-error))

(ert-deftest vhdl-tpl-test-body-questions-come-before-header-questions ()
  (let* ((asked nil)
         (vhdl-tpl-read-function
          (lambda (var default) (push var asked) (or default "x"))))
    (vhdl-tpl-render "{{>header.vhd}}\n{{entity}}")
    (should (equal (nreverse asked) '("entity" "desc")))))

;;;; Bundled files

(ert-deftest vhdl-tpl-test-bundled-files-exist ()
  (dolist (name '("entity_arch" "two_process" "two_process_pkg" "package"
                  "testbench" "fsm" "counter" "sync_2ff" "reset_sync"
                  "fifo_sync" "ram_sdp" "edge_detect" "top_level"
                  "xdc_constraints" "sdc_constraints" "debounce" "pulse_sync"
                  "fifo_async" "pwm" "lfsr" "shift_reg" "rom_lut" "mac_dsp"
                  "uart_tx" "uart_rx" "spi_master" "axis_skid"
                  "axi_lite_regs" "ghdl_makefile" "vivado_build"
                  "bus_sync_handshake" "avalon_mm_regs" "bfm_util_pkg"
                  "bfm_axis_pkg" "bfm_avalon_st_pkg" "bfm_axilite_pkg"
                  "bfm_avalon_mm_pkg" "bfm_uart_pkg" "bfm_spi_pkg"
                  "testbench_bfm" "spi_slave"))
    (should (assoc name (vhdl-tpl--list 'templates))))
  (should (>= (length (vhdl-tpl--list 'snippets)) 15)))

(ert-deftest vhdl-tpl-test-everything-has-a-description ()
  (dolist (kind '(templates snippets))
    (dolist (entry (vhdl-tpl--list kind))
      (should (vhdl-tpl--description (cdr entry))))))

(ert-deftest vhdl-tpl-test-everything-renders-cleanly ()
  (vhdl-tpl-test--with-defaults
   (dolist (kind '(templates snippets))
     (dolist (entry (vhdl-tpl--list kind))
       (let ((out (vhdl-tpl-render (vhdl-tpl--read-file (cdr entry)) nil
                                   "/tmp/some_name.vhd")))
         (should-not (string-match-p "{{" out))
         (should-not (string-match-p "}}" out))
         (should-not (string-match-p
                      "\\$\\(?:file\\|filename\\|stem\\|date\\|year\\|author\\|email\\)"
                      out))
         (should (<= (cl-count ?\uE000 out) 1)))))))

;;;; User directory

(ert-deftest vhdl-tpl-test-user-directory-wins ()
  (let* ((root (make-temp-file "vhdl-tpl" t))
         (vhdl-tpl-user-directory root))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "templates" root))
          (make-directory (expand-file-name "partials" root))
          (with-temp-file (expand-file-name "templates/counter.vhd" root)
            (insert "{{!mine}}\nmy counter\n"))
          (with-temp-file (expand-file-name "templates/extra.vhd" root)
            (insert "{{!extra}}\nextra\n"))
          (with-temp-file (expand-file-name "partials/header.vhd" root)
            (insert "-- my header\n"))
          (should (string-prefix-p root (cdr (assoc "counter"
                                                    (vhdl-tpl--list 'templates)))))
          (should (assoc "extra" (vhdl-tpl--list 'templates)))
          (should (assoc "fsm" (vhdl-tpl--list 'templates)))
          (vhdl-tpl-test--with-defaults
           (setq vhdl-tpl-user-directory root)
           (should (equal (vhdl-tpl-render "{{>header.vhd}}") "-- my header"))))
      (delete-directory root t))))

;;;; Insertion

(ert-deftest vhdl-tpl-test-insert-places-point-at-cursor ()
  (vhdl-tpl-test--with-defaults
   (with-temp-buffer
     (vhdl-tpl-insert 'templates "entity_arch" '(("entity" . "widget")))
     (should (eolp))
     (should (looking-back "^  " (line-beginning-position)))
     (should (equal (buffer-substring (1+ (point)) (+ 6 (point))) "begin"))
     (should (save-excursion (goto-char (point-min))
                             (search-forward "entity widget is" nil t)))
     (should-not (save-excursion (goto-char (point-min))
                                 (search-forward "\uE000" nil t))))))

(ert-deftest vhdl-tpl-test-unknown-name-is-an-error ()
  (should-error (vhdl-tpl-insert 'templates "does_not_exist")
                :type 'user-error))

(ert-deftest vhdl-tpl-test-snippet-is-indented-in-vhdl-mode ()
  (vhdl-tpl-test--with-defaults
   (with-temp-buffer
     (insert "architecture rtl of x is\nbegin\n  ")
     (vhdl-mode)
     (vhdl-tpl-insert 'snippets "process_comb")
     (should (equal (buffer-substring (point-min) (point-max))
                    (concat "architecture rtl of x is\nbegin\n"
                            "  p_comb : process (all)\n"
                            "  begin\n"
                            "    \n"
                            "  end process p_comb;")))
     (should (= (current-column) 4))
     (should (eolp)))))

(ert-deftest vhdl-tpl-test-new-file-keeps-name-of-extensionless-template ()
  (vhdl-tpl-test--with-defaults
   (let* ((dir (make-temp-file "vhdl-tpl" t))
          (file (expand-file-name "Makefile" dir)))
     (let ((vhdl-tpl--inhibit-auto-insert t))
       (vhdl-tpl-new-file "ghdl_makefile" file))
     (with-current-buffer (get-file-buffer file)
       (goto-char (point-min))
       (should (search-forward "GHDL  ?= ghdl" nil t))
       (should (search-forward "\t$(GHDL) -r" nil t))
       (set-buffer-modified-p nil)
       (kill-buffer)))))

;;;; auto-insert

(defmacro vhdl-tpl-test--with-setup (&rest body)
  "Run BODY with `vhdl-tpl-setup' applied to temporary global state."
  `(let ((auto-insert-alist (copy-alist auto-insert-alist))
         (auto-insert-query nil)
         (find-file-hook find-file-hook)
         (vhdl-mode-hook vhdl-mode-hook)
         (asked nil))
     (vhdl-tpl-setup)
     (cl-letf (((symbol-function 'completing-read)
                (lambda (_prompt _coll _pred _match _init _hist def)
                  (push def asked)
                  def)))
       ,@body)))

(defun vhdl-tpl-test--visit (name)
  "Visit the not yet existing NAME in a fresh directory, return the buffer."
  (find-file-noselect (expand-file-name name (make-temp-file "vhdl-tpl" t))))

(ert-deftest vhdl-tpl-test-auto-insert-suggests-by-file-name ()
  (vhdl-tpl-test--with-defaults
   (vhdl-tpl-test--with-setup
    (dolist (case '(("foo_tb.vhd" . "testbench")
                    ("tb_foo.vhd" . "testbench")
                    ("foo_pkg.vhd" . "package")
                    ("foo_top.vhd" . "top_level")
                    ("foo.vhd" . "entity_arch")
                    ("foo.vhdl" . "entity_arch")))
      (setq asked nil)
      (with-current-buffer (vhdl-tpl-test--visit (car case))
        (should (equal asked (list (cdr case))))
        (should (> (buffer-size) 0))
        (should vhdl-tpl-mode)
        (set-buffer-modified-p nil)
        (kill-buffer))))))

(ert-deftest vhdl-tpl-test-auto-insert-uses-file-name-as-entity ()
  (vhdl-tpl-test--with-defaults
   (vhdl-tpl-test--with-setup
    (with-current-buffer (vhdl-tpl-test--visit "foo_tb.vhd")
      (goto-char (point-min))
      (should (search-forward "entity foo_tb is" nil t))
      (should (search-forward "entity work.foo\n" nil t))
      (set-buffer-modified-p nil)
      (kill-buffer)))))

(ert-deftest vhdl-tpl-test-auto-insert-constraint-files ()
  (vhdl-tpl-test--with-defaults
   (vhdl-tpl-test--with-setup
    (dolist (case '(("board.xdc" . "create_clock")
                    ("board.sdc" . "create_clock")))
      (with-current-buffer (vhdl-tpl-test--visit (car case))
        (goto-char (point-min))
        (should (search-forward (cdr case) nil t))
        (should (null asked))
        (set-buffer-modified-p nil)
        (kill-buffer))))))

(ert-deftest vhdl-tpl-test-auto-insert-leaves-existing-files-alone ()
  (vhdl-tpl-test--with-defaults
   (vhdl-tpl-test--with-setup
    (let ((file (make-temp-file "vhdl-tpl" nil ".vhd")))
      (with-temp-file file (insert "-- mine\n"))
      (with-current-buffer (find-file-noselect file)
        (should (equal (buffer-string) "-- mine\n"))
        (kill-buffer))))))

(ert-deftest vhdl-tpl-test-new-file-inserts-exactly-once ()
  (vhdl-tpl-test--with-defaults
   (vhdl-tpl-test--with-setup
    (let ((file (expand-file-name "bar.vhd" (make-temp-file "vhdl-tpl" t))))
      (vhdl-tpl-new-file "counter" file)
      (with-current-buffer (get-file-buffer file)
        (should (null asked))
        (should (= 1 (how-many "^entity bar is" (point-min))))
        (set-buffer-modified-p nil)
        (kill-buffer))))))

(ert-deftest vhdl-tpl-test-key-prefix ()
  (should (eq (lookup-key vhdl-tpl-mode-map (kbd "C-c t t"))
              #'vhdl-tpl-insert-template))
  (should (eq (lookup-key vhdl-tpl-mode-map (kbd "C-c t s"))
              #'vhdl-tpl-insert-snippet))
  (should (eq (lookup-key vhdl-tpl-mode-map (kbd "C-c t n"))
              #'vhdl-tpl-new-file)))

;;; vhdl-tpl-test.el ends here
