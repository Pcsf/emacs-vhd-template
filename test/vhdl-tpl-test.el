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
                  "axi_lite_regs" "project_mk" "vivado_build"
                  "bus_sync_handshake" "avalon_mm_regs" "bfm_util_pkg"
                  "bfm_axis_pkg" "bfm_avalon_st_pkg" "bfm_axilite_pkg"
                  "bfm_avalon_mm_pkg" "bfm_uart_pkg" "bfm_spi_pkg"
                  "testbench_bfm" "spi_slave" "i2c_master" "i2c_slave"
                  "bfm_i2c_pkg" "two_process_skeleton" "two_process_tb"
                  "doc_icd" "doc_srs" "doc_hdd" "doc_vplan" "doc_test_report"
                  "doc_rtm" "doc_adr" "doc_review" "doc_release"))
    (should (assoc name (vhdl-tpl--list 'templates))))
  (should (>= (length (vhdl-tpl--list 'snippets)) 16)))

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

;;;; Org documents

(ert-deftest vhdl-tpl-test-org-documents-are-well-formed ()
  "Every .org template renders to an Org document with a title and headlines."
  (require 'org)
  (vhdl-tpl-test--with-defaults
   (let ((docs (cl-remove-if-not
                (lambda (e) (string-suffix-p ".org" (cdr e)))
                (vhdl-tpl--list 'templates))))
     (should (>= (length docs) 9))
     (dolist (entry docs)
       (let ((out (vhdl-tpl-render (vhdl-tpl--read-file (cdr entry)) nil
                                   "/tmp/uart.org")))
         (should (string-prefix-p "#+TITLE: " out))
         (should (string-match-p "^#\\+AUTHOR: Test Author$" out))
         (should (string-match-p "^#\\+OPTIONS: .*\\^:nil" out))
         ;; The file name feeds the module name, as for VHDL templates.
         (should (string-match-p "uart" out))
         (with-temp-buffer
           (insert (string-replace vhdl-tpl--cursor "" out))
           (org-mode)
           (let* ((tree (org-element-parse-buffer))
                  (headlines (org-element-map tree 'headline #'identity))
                  (tables (org-element-map tree 'table #'identity)))
             (should (>= (length headlines) 3))
             (should (>= (length tables) 1))
             ;; A revision history closes every document.
             (should (member "Revision history"
                             (mapcar (lambda (h)
                                       (org-element-property :raw-value h))
                                     headlines))))))))))

(ert-deftest vhdl-tpl-test-org-tables-are-aligned-on-insert ()
  "Inserting a document into an Org buffer re-aligns its tables."
  (require 'org)
  (vhdl-tpl-test--with-defaults
   (with-temp-buffer
     (org-mode)
     (setq buffer-file-name "/tmp/uart_icd.org")
     (vhdl-tpl-insert 'templates "doc_icd")
     (setq buffer-file-name nil)
     (goto-char (point-min))
     (should (search-forward "#+TITLE: ICD: uart_icd" nil t))
     ;; The port table: a cell holding an answer is as wide as the others.
     (should (re-search-forward "^| Port " nil t))
     (let ((header (buffer-substring (line-beginning-position) (line-end-position))))
       (forward-line 2)
       (should (looking-at "| clk "))
       (should (= (length header)
                  (- (line-end-position) (line-beginning-position))))
       (should (string-match-p "System clock, 100 MHz" (buffer-substring (line-beginning-position)
                                                             (line-end-position))))
       (forward-line 1)
       (should (= (length header)
                  (- (line-end-position) (line-beginning-position)))))
     (should-not (search-forward "\uE000" nil t)))))

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
          (file (expand-file-name "project.mk" dir)))
     (let ((vhdl-tpl--inhibit-auto-insert t))
       (vhdl-tpl-new-file "project_mk" file))
     (with-current-buffer (get-file-buffer file)
       (goto-char (point-min))
       (should (search-forward "TOOLCHAIN    := ghdl" nil t))
       (should (search-forward "GHDL_WAVE := ghw" nil t))
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
              #'vhdl-tpl-new-file))
  (should (eq (lookup-key vhdl-tpl-mode-map (kbd "C-c t b"))
              #'vhdl-tpl-new-block)))

;;;; New two-process block

(defun vhdl-tpl-test--slurp (file)
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun vhdl-tpl-test--new-block (name dir)
  "Run `vhdl-tpl-new-block' without prompts and close the buffer it opens."
  (vhdl-tpl-test--with-defaults
   (let ((vhdl-tpl--inhibit-auto-insert t))
     (vhdl-tpl-new-block name dir)
     (set-buffer-modified-p nil)
     (kill-buffer))))

(ert-deftest vhdl-tpl-test-new-block-creates-a-project ()
  (let ((dir (make-temp-file "vhdl-tpl" t)))
    (vhdl-tpl-test--new-block "blk" dir)
    (let ((pkg (vhdl-tpl-test--slurp (expand-file-name "src/blk_pkg.vhd" dir)))
          (rtl (vhdl-tpl-test--slurp (expand-file-name "src/blk.vhd" dir)))
          (tb  (vhdl-tpl-test--slurp (expand-file-name "tb/tb_blk.vhd" dir)))
          (mk  (vhdl-tpl-test--slurp (expand-file-name "project.mk" dir))))
      (should (string-match-p "^package blk_pkg is" pkg))
      (should (string-match-p "blki : in  blk_in_type" pkg))
      (should (string-match-p "^use work\\.blk_pkg\\.all;" rtl))
      (should (string-match-p "^entity blk is" rtl))
      (should (string-match-p "signal r, rin : reg_type := REG_RESET;" rtl))
      (should (string-match-p "^entity tb_blk is" tb))
      (should (string-match-p "entity work\\.blk$" tb))
      (should (string-match-p "^GHDL_TOP  := tb_blk$" mk))
      (should (string-match-p "^TESTS     := tb_blk$" mk))
      (should (string-match-p "^PROJECT_NAME := " mk))
      (dolist (text (list pkg rtl tb mk))
        (should-not (string-match-p "{{\\|}}\\|\uE000" text))))
    (should (equal (vhdl-tpl-test--slurp (expand-file-name "Makefile" dir))
                   "include mk/Makefile\n"))))

(ert-deftest vhdl-tpl-test-new-block-never-overwrites ()
  (let* ((dir (make-temp-file "vhdl-tpl" t))
         (rtl (expand-file-name "src/blk.vhd" dir)))
    (make-directory (file-name-directory rtl) t)
    (with-temp-file rtl (insert "-- mine\n"))
    (should-error (vhdl-tpl-test--new-block "blk" dir) :type 'user-error)
    (should (equal (vhdl-tpl-test--slurp rtl) "-- mine\n"))
    (should-not (file-exists-p (expand-file-name "src/blk_pkg.vhd" dir)))
    (should-not (file-exists-p (expand-file-name "project.mk" dir)))))

(ert-deftest vhdl-tpl-test-new-block-joins-an-existing-project ()
  (let* ((dir (make-temp-file "vhdl-tpl" t))
         (mk (expand-file-name "project.mk" dir))
         (makefile (expand-file-name "Makefile" dir)))
    (with-temp-file mk (insert "TESTS := tb_old\n"))
    (with-temp-file makefile (insert "# mine\n"))
    (vhdl-tpl-test--new-block "blk" dir)
    (should (equal (vhdl-tpl-test--slurp mk) "TESTS := tb_old\nTESTS += tb_blk\n"))
    (should-not (vhdl-tpl--add-test-case mk "tb_blk"))
    (should (equal (vhdl-tpl-test--slurp mk) "TESTS := tb_old\nTESTS += tb_blk\n"))
    (should (equal (vhdl-tpl-test--slurp makefile) "# mine\n"))))

;;; vhdl-tpl-test.el ends here
