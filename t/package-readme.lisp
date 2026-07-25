(in-package #:cl-tty-kit/test)

;;;; Documentation/code agreement.
;;;;
;;;; These assertions used to read README.md, which is why the README carried a
;;;; 341-line enumeration of every exported symbol plus a list of all 21
;;;; examples. The org standard caps the README at 150 lines, so the same
;;;; invariants now hold against the pages under docs/src/ that own each piece
;;;; of that content. The invariants themselves are unchanged: the documented
;;;; API cannot silently drift from the package, and the documented example
;;;; list cannot silently drift from examples/.

(defun %doc-string (relative-path)
  (uiop:read-file-string (cl-tty-kit/bootstrap:project-pathname relative-path)))

(defun %fenced-blocks (markdown)
  "Return each fenced code block in MARKDOWN as a plist of :SECTION (the
enclosing `## ` heading), :LANGUAGE, and :BODY."
  (let ((blocks '())
        (section nil)
        (in-block-p nil)
        (block-language nil)
        (block-lines '()))
    (with-input-from-string (stream markdown)
      (loop for line = (read-line stream nil nil)
            while line
            do (cond
                 ((and (not in-block-p)
                       (> (length line) 3)
                       (string= "## " (subseq line 0 3)))
                  (setf section line))
                 ((and (not in-block-p)
                       (> (length line) 3)
                       (string= "```" (subseq line 0 3)))
                  (setf in-block-p t
                        block-language (subseq line 3)
                        block-lines '()))
                 ((and in-block-p
                       (string= line "```"))
                  (push (list :section section
                              :language block-language
                              :body (format nil "~{~A~^~%~}" (nreverse block-lines)))
                        blocks)
                  (setf in-block-p nil
                        block-language nil
                        block-lines '()))
                 (in-block-p
                  (push line block-lines)))))
    (nreverse blocks)))

(defun %section-block-bodies (markdown section language)
  (loop for block in (%fenced-blocks markdown)
        when (and (equal (getf block :section) section)
                  (string= (getf block :language) language))
          collect (getf block :body)))

(defun %language-block-bodies (markdown language)
  (loop for block in (%fenced-blocks markdown)
        when (string= (getf block :language) language)
          collect (getf block :body)))

(defun %inline-code-spans (markdown)
  "Every `...` span in MARKDOWN, upcased. Spans inside fenced code blocks are
included too; that is harmless, because this only ever answers \"is this symbol
mentioned on the page?\"."
  (let ((spans '())
        (position 0))
    (loop
      (let ((open (position #\` markdown :start position)))
        (unless open (return))
        (let ((close (position #\` markdown :start (1+ open))))
          (unless close (return))
          (push (string-upcase (subseq markdown (1+ open) close)) spans)
          (setf position (1+ close)))))
    (nreverse spans)))

(defun %snippet-contains-p (snippet fragment)
  (not (null (search fragment snippet))))

(defun %assert-fragments-present (snippet fragments message-template)
  (dolist (fragment fragments)
    (assert (%snippet-contains-p snippet fragment) ()
            message-template
            fragment)))

(defun %some-snippet-contains-all-p (snippets fragments)
  (some (lambda (snippet)
          (every (lambda (fragment) (%snippet-contains-p snippet fragment))
                 fragments))
        snippets))

(defun %filesystem-example-script-files ()
  (let* ((project-root (cl-tty-kit/bootstrap:project-root))
         (example-paths (directory (merge-pathnames #P"examples/*.lisp" project-root))))
    (sort (loop for path in example-paths
                for relative = (enough-namestring path project-root)
                unless (string= relative "examples/bootstrap.lisp")
                  collect relative)
          #'string<)))

;;; --- API reference ---------------------------------------------------------

(defun %assert-api-reference-documents-symbol (api-spans symbol-name)
  (assert (member symbol-name api-spans :test #'string=) ()
          "~A is exported from CL-TTY-KIT but is not mentioned in docs/src/api-reference.md"
          symbol-name))

(defun %test-api-reference-coverage (api-doc external-symbols)
  (let ((api-spans (%inline-code-spans api-doc)))
    (do-test-case-bind (symbol-case (mapcar #'list external-symbols) (symbol-name))
      (%assert-api-reference-documents-symbol api-spans symbol-name))))

;;; --- Examples --------------------------------------------------------------

(defun %split-markdown-row (row)
  "Split a `| a | b |` table row into its trimmed cell strings."
  (let ((cells '())
        (start 1))
    (loop
      (let ((bar (position #\| row :start start)))
        (unless bar (return))
        (push (string-trim " " (subseq row start bar)) cells)
        (setf start (1+ bar))))
    (nreverse cells)))

(defun %examples-doc-entries (examples-doc)
  "Parse the two-column table rows out of docs/src/examples.md into an alist of
(\"examples/name.lisp\" . summary), sorted by path. Backticks are stripped from
the summary so the page may format symbol names as code while still matching
the plain summary registered in scripts/example-files.lisp."
  (let ((entries '()))
    (with-input-from-string (stream examples-doc)
      (loop for line = (read-line stream nil nil)
            while line
            do (let ((trimmed (string-trim " " line)))
                 (when (and (plusp (length trimmed))
                            (char= #\| (char trimmed 0)))
                   (let ((cells (%split-markdown-row trimmed)))
                     (when (= 2 (length cells))
                       (let ((file (string-trim "` " (first cells)))
                             (summary (string-trim " " (remove #\` (second cells)))))
                         (when (and (> (length file) 5)
                                    (string= ".lisp" (subseq file (- (length file) 5))))
                           (push (cons (concatenate 'string "examples/" file) summary)
                                 entries)))))))))
    (sort (nreverse entries) #'string< :key #'car)))

(defun %example-cases (example-files)
  (mapcar (lambda (example)
            (list example (cl-user::example-summary example)))
          example-files))

(defun %assert-example-documented (doc-entries example summary)
  (let ((entry (assoc example doc-entries :test #'string=)))
    (assert entry ()
            "~A should be listed in docs/src/examples.md"
            example)
    (assert (string= (cdr entry) summary) ()
            "~A's summary in docs/src/examples.md should be ~S but was ~S"
            example
            summary
            (cdr entry))))

(defun %test-example-registration (examples-doc registered-example-files filesystem-example-files)
  (assert (equal registered-example-files filesystem-example-files) ()
          "scripts/example-files.lisp should register every runnable example exactly once.~%Registered: ~S~%Filesystem: ~S"
          registered-example-files
          filesystem-example-files)
  (let ((doc-entries (%examples-doc-entries examples-doc)))
    ;; Counting as well as looking each one up catches the reverse drift: an
    ;; example deleted from examples/ but left behind in the table.
    (assert (= (length doc-entries) (length registered-example-files)) ()
            "docs/src/examples.md lists ~D examples but ~D are registered.~%Listed: ~S"
            (length doc-entries)
            (length registered-example-files)
            (mapcar #'car doc-entries))
    (do-test-case-bind (example-case (%example-cases registered-example-files)
                                     (example summary))
      (%assert-example-documented doc-entries example summary))))

;;; --- Command documentation -------------------------------------------------

(defun %assert-command-documented (development-doc command)
  (assert (%snippet-contains-p development-doc command) ()
          "~A should be documented in docs/src/development.md"
          command))

(defun %test-development-command-docs (development-doc)
  (do-test-case-bind (command-case (mapcar #'list +expected-development-commands+) (command))
    (%assert-command-documented development-doc command)))

;;; --- Prose snippets --------------------------------------------------------

(defun %test-readme-quick-start (quick-start-snippets)
  ;; The README is the entry point, so it gets exactly one runnable example.
  ;; More than one means it is drifting back into being the manual.
  (assert (= 1 (length quick-start-snippets)) ()
          "README.md should contain exactly one Quick Start Lisp snippet, found ~D"
          (length quick-start-snippets))
  (%assert-fragments-present
   (first quick-start-snippets)
   +expected-quick-start-fragments+
   "README.md Quick Start snippet should include ~S"))

(defun %test-input-decoding-snippets (input-decoding-doc)
  ;; Matched against any Lisp block on the page rather than a fixed position,
  ;; so reordering or adding examples does not break the check.
  (let ((snippets (%language-block-bodies input-decoding-doc "lisp")))
    (assert (%some-snippet-contains-all-p snippets +expected-streaming-fragments+) ()
            "docs/src/input-decoding.md should show the streaming decoder example ~S"
            +expected-streaming-fragments+)
    (assert (%some-snippet-contains-all-p snippets +expected-paste-fragments+) ()
            "docs/src/input-decoding.md should show the bracketed-paste example ~S"
            +expected-paste-fragments+)))

;;; --- Entry point -----------------------------------------------------------

(defun test-package ()
  (test-utils)
  (test-char-width-api)
  (let* ((pkg (find-package :cl-tty-kit))
         (system-metadata (%system-definition-metadata-plist :cl-tty-kit))
         (readme (%doc-string "README.md"))
         (api-doc (%doc-string "docs/src/api-reference.md"))
         (examples-doc (%doc-string "docs/src/examples.md"))
         (development-doc (%doc-string "docs/src/development.md"))
         (input-decoding-doc (%doc-string "docs/src/input-decoding.md"))
         (quick-start-snippets (%section-block-bodies readme "## Quick Start" "lisp"))
         (external-symbols (%package-external-symbol-names pkg))
         (registered-example-files (sort (copy-list (cl-user::example-script-files))
                                         #'string<))
         (filesystem-example-files (%filesystem-example-script-files)))
    (%test-package-metadata system-metadata)
    (%test-package-exports pkg external-symbols)
    (%test-api-reference-coverage api-doc external-symbols)
    (%test-example-registration examples-doc
                                registered-example-files
                                filesystem-example-files)
    (%test-development-command-docs development-doc)
    (%test-readme-quick-start quick-start-snippets)
    (%test-input-decoding-snippets input-decoding-doc)
    (%assert-non-empty-public-documentation pkg)
    t))
