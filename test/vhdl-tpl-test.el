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
         (vhdl-tpl-confirm-function #'ignore)
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
                  "bus_sync_handshake" "avalon_mm_regs" "tb_util_pkg" "sb_pkg"
                  "bfm_axis_pkg" "bfm_avalon_st_pkg" "bfm_axilite_pkg"
                  "bfm_avalon_mm_pkg" "bfm_uart_pkg" "bfm_spi_pkg"
                  "testbench_bfm" "spi_slave" "i2c_master" "i2c_slave"
                  "bfm_i2c_pkg" "two_process_skeleton" "two_process_tb"
                  "doc_icd" "doc_srs" "doc_hdd" "doc_vplan" "doc_test_report"
                  "doc_rtm" "doc_adr" "doc_review" "doc_release"))
    (should (assoc name (vhdl-tpl--list 'templates))))
  (should (>= (length (vhdl-tpl--list 'snippets)) 17)))

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
     (setq buffer-file-name "/tmp/a_long_block_name_hdd.org")
     (vhdl-tpl-insert 'templates "doc_hdd")
     (setq buffer-file-name nil)
     (goto-char (point-min))
     (should (search-forward "#+TITLE: Design description: a_long_block_name" nil t))
     ;; The file table: a cell holding an answer is as wide as the others.
     (should (re-search-forward "^| File " nil t))
     (let ((header (buffer-substring (line-beginning-position) (line-end-position))))
       (forward-line 2)
       (should (looking-at "| ~src/a_long_block_name_pkg.vhd~ "))
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

(defun vhdl-tpl-test--compile-order (dir)
  "The file names listed in DIR/.compile_order, comments dropped."
  (cl-remove-if (lambda (l) (or (string-empty-p l) (string-prefix-p "#" l)))
                (split-string (vhdl-tpl-test--slurp
                               (expand-file-name ".compile_order" dir))
                              "\n")))

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
      (should (string-match-p "^use work\\.tb_util_pkg\\.all;" tb))
      (should (string-match-p "^package tb_util_pkg is"
                              (vhdl-tpl-test--slurp
                               (expand-file-name "tb/tb_util_pkg.vhd" dir))))
      (should (equal (vhdl-tpl-test--compile-order (expand-file-name "src" dir))
                     '("blk_pkg.vhd" "blk.vhd")))
      (should (equal (vhdl-tpl-test--compile-order (expand-file-name "tb" dir))
                     '("tb_util_pkg.vhd" "tb_blk.vhd")))
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

(ert-deftest vhdl-tpl-test-new-block-keeps-the-project-tb-util-and-order ()
  (let* ((dir (make-temp-file "vhdl-tpl" t))
         (util (expand-file-name "tb/tb_util_pkg.vhd" dir))
         (order (expand-file-name "tb/.compile_order" dir)))
    (make-directory (file-name-directory util) t)
    (with-temp-file util (insert "-- the project's own\n"))
    (with-temp-file order (insert "# mine\ntb_util_pkg.vhd\ntb_old.vhd\n"))
    (vhdl-tpl-test--new-block "blk" dir)
    (should (equal (vhdl-tpl-test--slurp util) "-- the project's own\n"))
    (should (equal (vhdl-tpl-test--slurp order)
                   "# mine\ntb_util_pkg.vhd\ntb_old.vhd\ntb_blk.vhd\n"))
    ;; A second block changes nothing but its own line.
    (vhdl-tpl-test--new-block "two" dir)
    (should (equal (vhdl-tpl-test--compile-order (expand-file-name "tb" dir))
                   '("tb_util_pkg.vhd" "tb_old.vhd" "tb_blk.vhd" "tb_two.vhd")))))

(ert-deftest vhdl-tpl-test-compile-order-puts-the-package-first ()
  (let* ((dir (make-temp-file "vhdl-tpl" t))
         (order (expand-file-name ".compile_order" dir)))
    (with-temp-file order (insert "tb_old.vhd\n"))
    (vhdl-tpl--update-compile-order dir '("tb_util_pkg.vhd") '("tb_new.vhd"))
    (should (equal (vhdl-tpl-test--compile-order dir)
                   '("tb_util_pkg.vhd" "tb_old.vhd" "tb_new.vhd")))))

;;;; Documents: file names, skeletons, links

(defconst vhdl-tpl-test--kinds
  '("icd" "srs" "hdd" "vplan" "rtm" "adr" "review" "release" "test_report"))

(defconst vhdl-tpl-test--examples
  (expand-file-name "../examples/" (file-name-directory
                                    (or load-file-name buffer-file-name))))

(ert-deftest vhdl-tpl-test-stem-drops-document-suffixes ()
  (dolist (case '(("/tmp/uart_icd.org" . "uart")
                  ("/tmp/uart_test_report.org" . "uart")
                  ("/tmp/uart_adr_003.org" . "uart")
                  ("/tmp/spi_master_vplan.org" . "spi_master")
                  ("/tmp/notes.org" . "notes")
                  ;; Only Org files: a VHDL entity may be called foo_review.
                  ("/tmp/foo_review.vhd" . "foo_review")))
    (should (equal (cdr (assoc "stem" (vhdl-tpl--builtins (car case))))
                   (cdr case)))))

(defun vhdl-tpl-test--render-docs (dir &optional block)
  "Render every document template into DIR as BLOCK_KIND.org; return DIR."
  (vhdl-tpl-test--with-defaults
   (dolist (kind vhdl-tpl-test--kinds)
     (vhdl-tpl--write (concat "doc_" kind)
                      (expand-file-name (format "%s_%s.org" (or block "uart") kind)
                                        dir)
                      nil)))
  dir)

(defconst vhdl-tpl-test--example-content
  "SOFT_RST\\|SCRATCH\\|SLVERR\\|0x4000\\|Level-triggered\\|p_tw_[a-z]\\|\\_<busy\\_>\\|W1C"
  "Text of the worked example, which a skeleton must not carry.")

(ert-deftest vhdl-tpl-test-skeletons-carry-no-example-content ()
  (let ((dir (vhdl-tpl-test--render-docs (make-temp-file "vhdl-tpl" t))))
    (dolist (kind vhdl-tpl-test--kinds)
      (let ((text (vhdl-tpl-test--slurp
                   (expand-file-name (format "uart_%s.org" kind) dir))))
        (should-not (string-match-p vhdl-tpl-test--example-content text))
        ;; Guidance is there, as Org comment lines that are not exported.
        (should (string-match-p "^# [A-Z]" text))
        (should (string-match-p "uart" text)))))
  ;; The checker does flag the example it is meant to keep out.
  (should (string-match-p vhdl-tpl-test--example-content
                          (vhdl-tpl-test--slurp
                           (expand-file-name "demo_icd.org"
                                             vhdl-tpl-test--examples)))))

(defun vhdl-tpl-test--custom-ids (file)
  (let (ids)
    (with-temp-buffer
      (insert-file-contents file)
      (while (re-search-forward "^[ \t]*:CUSTOM_ID:[ \t]+\\(\\S-+\\)" nil t)
        (push (match-string 1) ids)))
    ids))

(defun vhdl-tpl-test--broken-links (dir)
  "Links in the Org files of DIR that point at a missing file or CUSTOM_ID."
  (let (broken (count 0))
    (dolist (file (directory-files dir t "\\.org\\'"))
      (with-temp-buffer
        (insert-file-contents file)
        (while (re-search-forward
                "\\[\\[\\(?:file:\\([^]:]+\\)::\\)?#\\([^]]+\\)\\]" nil t)
          (cl-incf count)
          (let ((target (if (match-string 1)
                            (expand-file-name (match-string 1) dir)
                          file))
                (id (match-string 2)))
            (unless (and (file-exists-p target)
                         (member id (vhdl-tpl-test--custom-ids target)))
              (push (format "%s -> %s#%s" (file-name-nondirectory file)
                            (file-name-nondirectory target) id)
                    broken))))))
    (cons count broken)))

(defconst vhdl-tpl-test--section-number
  "\\_<[Ss]ections? [0-9]\\|\\_<\\(?:ICD\\|HDD\\|SRS\\) [0-9]"
  "A reference to another place by its section number.")

(ert-deftest vhdl-tpl-test-document-links-resolve ()
  (let ((dir (vhdl-tpl-test--render-docs (make-temp-file "vhdl-tpl" t))))
    (dolist (d (list dir vhdl-tpl-test--examples))
      (let ((result (vhdl-tpl-test--broken-links d)))
        (should (> (car result) 10))
        (should (equal (cdr result) nil)))
      (dolist (file (directory-files d t "\\.org\\'"))
        (should-not (string-match-p vhdl-tpl-test--section-number
                                    (vhdl-tpl-test--slurp file)))))
    ;; Both checkers catch what they are for.
    (with-temp-file (expand-file-name "uart_planted.org" dir)
      (insert "See [[file:uart_icd.org::#no-such-id][the ICD]].\n"))
    (should (equal (cdr (vhdl-tpl-test--broken-links dir))
                   '("uart_planted.org -> uart_icd.org#no-such-id")))
    (should (string-match-p vhdl-tpl-test--section-number
                            "the recovery sequence of ICD section 5.2"))
    (should (string-match-p vhdl-tpl-test--section-number "| TC-13 | ICD 4.4 |"))))

(ert-deftest vhdl-tpl-test-examples-are-well-formed ()
  (require 'org)
  (dolist (kind vhdl-tpl-test--kinds)
    (let ((file (expand-file-name (format "demo_%s.org" kind)
                                  vhdl-tpl-test--examples)))
      (should (file-exists-p file))
      (with-temp-buffer
        (insert-file-contents file)
        (should (looking-at "#\\+TITLE: "))
        (should-not (string-match-p "{{\\|}}" (buffer-string)))
        (delay-mode-hooks (org-mode))
        (should (>= (length (org-element-map (org-element-parse-buffer)
                                'headline #'identity))
                    3))))))

(ert-deftest vhdl-tpl-test-icd-has-one-row-per-bit ()
  (let ((dir (vhdl-tpl-test--render-docs (make-temp-file "vhdl-tpl" t))))
    (dolist (file (list (expand-file-name "uart_icd.org" dir)
                        (expand-file-name "demo_icd.org" vhdl-tpl-test--examples)))
      (with-temp-buffer
        (insert-file-contents file)
        (should (re-search-forward "^| Bits " nil t))
        (goto-char (point-min))
        (while (re-search-forward "^| Bits " nil t)
          (forward-line 2)
          (while (looking-at "|")
            ;; A row with an empty first cell continues the one above it.
            (should-not (looking-at "| +|"))
            (forward-line 1)))))
    (dolist (file (directory-files dir t "\\.org\\'"))
      (with-temp-buffer
        (insert-file-contents file)
        ;; As displayed: a link shows its description only.
        (goto-char (point-min))
        (while (re-search-forward "\\[\\[[^]]*\\]\\[\\([^]]*\\)\\]\\]" nil t)
          (replace-match "\\1"))
        (goto-char (point-min))
        (while (not (eobp))
          (should (<= (- (line-end-position) (line-beginning-position)) 100))
          (forward-line 1))))))

;;;; The document set of a block

(defun vhdl-tpl-test--new-docs (name dir &optional reader)
  "Run `vhdl-tpl-new-docs' without prompts and close the buffer it opens."
  (vhdl-tpl-test--with-defaults
   (let ((vhdl-tpl--inhibit-auto-insert t)
         (vhdl-tpl-read-function (or reader vhdl-tpl-read-function)))
     (vhdl-tpl-new-docs name dir)
     (set-buffer-modified-p nil)
     (kill-buffer))))

(ert-deftest vhdl-tpl-test-new-docs-writes-the-set-asking-once ()
  (let* ((dir (make-temp-file "vhdl-tpl" t))
         (asked nil)
         (reader (lambda (var default)
                   (push var asked)
                   (if (equal var "prefix") "UART" default))))
    (vhdl-tpl-test--new-docs "uart" dir reader)
    (dolist (kind '("icd" "srs" "hdd" "vplan" "rtm"))
      (let ((text (vhdl-tpl-test--slurp
                   (expand-file-name (format "doc/uart_%s.org" kind) dir))))
        (should (string-match-p "^#\\+TITLE: .*uart" text))
        (should-not (string-match-p "{{\\|}}\\|\uE000" text))))
    (should-not (file-exists-p (expand-file-name "doc/uart_adr.org" dir)))
    ;; Each question once for the whole set, and never the block name.
    (should (equal (length asked) (length (delete-dups (copy-sequence asked)))))
    (should (member "prefix" asked))
    (should-not (member "module" asked))
    (should (string-match-p "UART-001"
                            (vhdl-tpl-test--slurp
                             (expand-file-name "doc/uart_srs.org" dir))))
    (should-not (cdr (vhdl-tpl-test--broken-links (expand-file-name "doc" dir))))))

(ert-deftest vhdl-tpl-test-new-docs-never-overwrites ()
  (let* ((dir (make-temp-file "vhdl-tpl" t))
         (icd (expand-file-name "doc/uart_icd.org" dir)))
    (make-directory (file-name-directory icd) t)
    (with-temp-file icd (insert "mine\n"))
    ;; The missing documents are added around the one that exists.
    (vhdl-tpl-test--new-docs "uart" dir)
    (should (equal (vhdl-tpl-test--slurp icd) "mine\n"))
    (should (file-exists-p (expand-file-name "doc/uart_srs.org" dir)))
    (should-error (vhdl-tpl-test--new-docs "uart" dir) :type 'user-error)))

(ert-deftest vhdl-tpl-test-answers-are-kept-for-later-documents ()
  (let* ((dir (make-temp-file "vhdl-tpl" t))
         (reader (lambda (var default)
                   (cond ((equal var "prefix") "UART")
                         ((equal var "version") "2.1.0")
                         (t default)))))
    (vhdl-tpl-test--new-docs "uart" dir reader)
    (should (equal (cdr (assoc "prefix" (vhdl-tpl--stored-answers
                                         (expand-file-name "doc/uart_adr.org" dir))))
                   "UART"))
    ;; A later document of the same block proposes them; another block does not.
    (vhdl-tpl-test--with-defaults
     (let ((out (vhdl-tpl-render
                 (vhdl-tpl--read-file (vhdl-tpl--file 'templates "doc_release"))
                 nil (expand-file-name "doc/uart_release.org" dir))))
       (should (string-match-p "^#\\+TITLE: Release 2\\.1\\.0: uart" out)))
     (let ((out (vhdl-tpl-render
                 (vhdl-tpl--read-file (vhdl-tpl--file 'templates "doc_release"))
                 nil (expand-file-name "doc/spi_release.org" dir))))
       (should (string-match-p "^#\\+TITLE: Release 1\\.0\\.0: spi" out))))))

(ert-deftest vhdl-tpl-test-rtm-and-report-are-column-views ()
  (require 'org)
  (let* ((dir (make-temp-file "vhdl-tpl" t))
         (doc (expand-file-name "doc" dir)))
    (vhdl-tpl-test--new-docs "uart" dir)
    ;; The matrix is filled from the requirement headlines when it is written.
    (let ((rtm (vhdl-tpl-test--slurp (expand-file-name "uart_rtm.org" doc))))
      (should (string-match-p "^#\\+BEGIN: columnview .*uart_srs\\.org" rtm))
      (should (string-match-p "^| REQ-001 " rtm)))
    ;; A requirement added to the SRS shows up after an update, nowhere retyped.
    (with-temp-buffer
      (insert-file-contents (expand-file-name "uart_srs.org" doc))
      (goto-char (point-max))
      (insert "\n* More\n** REQ-777 Planted requirement\n:PROPERTIES:\n"
              ":CUSTOM_ID: REQ-777\n:METHOD: T\n:TEST: TC-77\n:END:\n")
      (write-region nil nil (expand-file-name "uart_srs.org" doc)))
    (vhdl-tpl--finish-org (expand-file-name "uart_rtm.org" doc))
    (let ((rtm (vhdl-tpl-test--slurp (expand-file-name "uart_rtm.org" doc))))
      (should (string-match-p "^| REQ-777 Planted requirement +| T +|.*TC-77" rtm)))
    ;; The test report takes its rows from the plan in the same way.
    (vhdl-tpl-test--with-defaults
     (vhdl-tpl--write "doc_test_report"
                      (expand-file-name "uart_test_report.org" doc) nil))
    (let ((report (vhdl-tpl-test--slurp
                   (expand-file-name "uart_test_report.org" doc))))
      (should (string-match-p "^#\\+BEGIN: columnview .*uart_vplan\\.org" report))
      (should (string-match-p "^| TC-01 " report)))))

;;;; Port table from the entity

(ert-deftest vhdl-tpl-test-ports-are-read-from-the-entity ()
  (let ((file (make-temp-file "vhdl-tpl" nil ".vhd")))
    (with-temp-file file
      (insert "entity widget is\n  generic (\n    G_WIDTH : positive := 8\n  );\n"
              "  port (\n"
              "    clk  : in  std_logic;\n"
              "    rst  : in  std_logic;  -- synchronous (active high)\n"
              "    a, b : in  std_logic_vector(G_WIDTH - 1 downto 0);\n"
              "    addr : in  unsigned(3 downto 0) := (others => '0');\n"
              "    sda  : inout std_logic;\n"
              "    n    : out natural range 0 to 7  -- count\n"
              "  );\nend entity widget;\n"
              "architecture rtl of widget is\n"
              "  signal fake : std_logic;\nbegin\n"
              "  u : entity work.x port map (clk => clk);\nend;\n"))
    (should (equal (vhdl-tpl--port-rows file)
                   '(("clk" "in" "1" "")
                     ("rst" "in" "1" "synchronous (active high)")
                     ("a" "in" "G_WIDTH" "")
                     ("b" "in" "G_WIDTH" "")
                     ("addr" "in" "4" "")
                     ("sda" "inout" "1" "")
                     ("n" "out" "natural range 0 to 7" "count"))))))

(ert-deftest vhdl-tpl-test-icd-port-table-follows-the-block ()
  (require 'org)
  (let ((dir (make-temp-file "vhdl-tpl" t)))
    (vhdl-tpl-test--new-block "blk" dir)
    (vhdl-tpl-test--new-docs "blk" dir)
    (let ((icd (vhdl-tpl-test--slurp (expand-file-name "doc/blk_icd.org" dir))))
      (should (string-match-p "^#\\+BEGIN: vhdl-ports :file \"\\.\\./src/blk\\.vhd\"" icd))
      (should (string-match-p "^| clk +| in +| +1 +|" icd))
      ;; Record ports are listed by field, from the package.
      (should (string-match-p "^| blki\\.start +| in +| +1 +|" icd))
      (should (string-match-p "^| blko\\.done +| out +| +1 +|" icd)))
    ;; A port added to the VHDL arrives with the next update.
    (let ((pkg (expand-file-name "src/blk_pkg.vhd" dir)))
      (with-temp-buffer
        (insert-file-contents pkg)
        (search-forward "start : std_logic;")
        (insert "\n    len   : std_logic_vector(7 downto 0);  -- words to move")
        (write-region nil nil pkg)))
    (vhdl-tpl--finish-org (expand-file-name "doc/blk_icd.org" dir))
    (should (string-match-p "^| blki\\.len +| in +| +8 +| words to move"
                            (vhdl-tpl-test--slurp
                             (expand-file-name "doc/blk_icd.org" dir))))))

(ert-deftest vhdl-tpl-test-port-table-without-a-source-is-left-empty ()
  (require 'org)
  (let ((dir (make-temp-file "vhdl-tpl" t)))
    (vhdl-tpl-test--new-docs "uart" dir)
    (let ((icd (vhdl-tpl-test--slurp (expand-file-name "doc/uart_icd.org" dir))))
      (should (string-match-p "^| Port +| Dir +| Width +| Description +|" icd))
      (should (string-match-p "^# .*src/uart\\.vhd" icd)))))

;;;; Question texts and needed templates

(ert-deftest vhdl-tpl-test-question-text-is-the-prompt ()
  (let (prompts)
    (cl-letf (((symbol-function 'read-string)
               (lambda (prompt &rest _) (push prompt prompts) "x")))
      (should (equal (vhdl-tpl-render "{{?a: The thing}}\n{{a|one}} {{b}}\n")
                     "x x\n")))
    (should (equal (nreverse prompts) '("The thing (default one): " "b: ")))))

(ert-deftest vhdl-tpl-test-needed-templates-are-declared ()
  (should (equal (vhdl-tpl--requires "top_level") '("reset_sync" "counter")))
  (should (equal (vhdl-tpl--requires "counter") nil))
  (dolist (name '("testbench" "two_process_tb" "bfm_axis_pkg" "bfm_i2c_pkg"
                  "bfm_uart_pkg" "bfm_spi_pkg" "bfm_axilite_pkg"
                  "bfm_avalon_mm_pkg" "bfm_avalon_st_pkg" "sb_pkg"))
    (should (equal (vhdl-tpl--requires name) '("tb_util_pkg"))))
  (should (equal (vhdl-tpl--requires "testbench_bfm")
                 '("tb_util_pkg" "bfm_axis_pkg")))
  (vhdl-tpl-test--with-defaults
   (should-not (string-match-p "{{" (vhdl-tpl-render "{{+counter}}\nbody\n")))))

(ert-deftest vhdl-tpl-test-new-file-offers-the-needed-templates ()
  (vhdl-tpl-test--with-defaults
   (let* ((dir (make-temp-file "vhdl-tpl" t))
          (counter (expand-file-name "counter.vhd" dir))
          (vhdl-tpl--inhibit-auto-insert t)
          (questions nil))
     (with-temp-file counter (insert "-- mine\n"))
     ;; Declined: nothing is written.
     (let ((vhdl-tpl-confirm-function
            (lambda (prompt) (push prompt questions) nil)))
       (vhdl-tpl-new-file "top_level" (expand-file-name "a_top.vhd" dir)))
     (set-buffer-modified-p nil) (kill-buffer)
     (should (equal (length questions) 1))
     (should (string-match-p "reset_sync\\.vhd" (car questions)))
     (should-not (string-match-p "counter\\.vhd" (car questions)))
     (should-not (file-exists-p (expand-file-name "reset_sync.vhd" dir)))
     ;; Accepted: the missing one appears, the existing one is left alone.
     (let ((vhdl-tpl-confirm-function (lambda (_prompt) t)))
       (vhdl-tpl-new-file "top_level" (expand-file-name "b_top.vhd" dir)))
     (set-buffer-modified-p nil) (kill-buffer)
     (should (string-match-p "^entity reset_sync is"
                             (vhdl-tpl-test--slurp
                              (expand-file-name "reset_sync.vhd" dir))))
     (should (equal (vhdl-tpl-test--slurp counter) "-- mine\n"))
     ;; Nothing missing, nothing asked.
     (setq questions nil)
     (let ((vhdl-tpl-confirm-function
            (lambda (prompt) (push prompt questions) nil)))
       (vhdl-tpl-new-file "top_level" (expand-file-name "c_top.vhd" dir)))
     (set-buffer-modified-p nil) (kill-buffer)
     (should (null questions)))))

;;;; Chooser

(defun vhdl-tpl-test--offered (&rest args)
  "The names `vhdl-tpl--complete' offers when called with ARGS."
  (let (offered)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_prompt coll &rest _)
                 (setq offered (all-completions "" coll))
                 "")))
      (apply #'vhdl-tpl--complete args))
    offered))

(ert-deftest vhdl-tpl-test-chooser-filters-by-file-type ()
  (let ((all (vhdl-tpl-test--offered 'templates "T: "))
        (vhdl (vhdl-tpl-test--offered 'templates "T: " nil "vhd"))
        (org (vhdl-tpl-test--offered 'templates "T: " nil "org")))
    (dolist (name '("entity_arch" "doc_icd" "project_mk" "xdc_constraints"))
      (should (member name all)))
    (should (member "entity_arch" vhdl))
    (should (member "tb_util_pkg" vhdl))
    (dolist (name '("doc_icd" "project_mk" "xdc_constraints" "vivado_build"))
      (should-not (member name vhdl)))
    (should (equal vhdl (vhdl-tpl-test--offered 'templates "T: " nil "vhdl")))
    (should (member "doc_icd" org))
    (should-not (member "entity_arch" org))
    ;; A file type without templates of its own gets the whole list.
    (should (equal all (vhdl-tpl-test--offered 'templates "T: " nil "txt")))))

(ert-deftest vhdl-tpl-test-new-vhdl-file-is-offered-vhdl-only ()
  (vhdl-tpl-test--with-defaults
   (let ((auto-insert-alist (copy-alist auto-insert-alist))
         (auto-insert-query nil)
         (find-file-hook find-file-hook)
         (vhdl-mode-hook vhdl-mode-hook)
         (org-mode-hook (bound-and-true-p org-mode-hook))
         (offered nil))
     (vhdl-tpl-setup)
     (cl-letf (((symbol-function 'completing-read)
                (lambda (_prompt coll _pred _match _init _hist def)
                  (setq offered (all-completions "" coll))
                  def)))
       (with-current-buffer (vhdl-tpl-test--visit "foo.vhd")
         (should (member "fsm" offered))
         (should-not (member "doc_icd" offered))
         (should-not (member "project_mk" offered))
         (set-buffer-modified-p nil)
         (kill-buffer))))))

(ert-deftest vhdl-tpl-test-chooser-groups-by-kind ()
  (dolist (case '(("doc_icd" . "Documents") ("fsm" . "Design")
                  ("bfm_axis_pkg" . "Verification") ("testbench" . "Verification")
                  ("tb_util_pkg" . "Verification") ("two_process_tb" . "Verification")
                  ("project_mk" . "Project files")
                  ("xdc_constraints" . "Project files")))
    (should (equal (vhdl-tpl--group (car case)
                                    (vhdl-tpl--file 'templates (car case)))
                   (cdr case)))))

;;;; Key bindings in the documents

(ert-deftest vhdl-tpl-test-mode-is-on-in-documents-only ()
  (require 'org)
  (let ((auto-insert-alist (copy-alist auto-insert-alist))
        (find-file-hook find-file-hook)
        (vhdl-mode-hook vhdl-mode-hook)
        (org-mode-hook org-mode-hook)
        (dir (make-temp-file "vhdl-tpl" t)))
    (vhdl-tpl-setup)
    (dolist (case '(("uart_icd.org" . t) ("uart_adr_002.org" . t)
                    ("notes.org" . nil)))
      (let ((file (expand-file-name (car case) dir)))
        (with-temp-file file (insert "* Heading\n"))
        (with-current-buffer (find-file-noselect file)
          (should (eq (and vhdl-tpl-mode t) (cdr case)))
          (kill-buffer)))))
  (should (eq (lookup-key vhdl-tpl-mode-map (kbd "C-c t d"))
              #'vhdl-tpl-new-docs)))

;;; vhdl-tpl-test.el ends here
