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

(describe "API reference coverage (docs/src/api-reference.md)"
  (let* ((pkg (find-package :cl-tty-kit))
         (external-symbols (%package-external-symbol-names pkg))
         (api-spans (%inline-code-spans (%doc-string "docs/src/api-reference.md"))))
    (dolist (symbol-name external-symbols)
      (it (format nil "~A is documented" symbol-name)
        (expect (member symbol-name api-spans :test #'string=))))))

(describe "example registration (examples/ vs scripts/example-files.lisp vs docs/src/examples.md)"
  (let* ((examples-doc (%doc-string "docs/src/examples.md"))
         (registered-example-files (sort (copy-list (cl-user::example-script-files)) #'string<))
         (filesystem-example-files (%filesystem-example-script-files))
         (doc-entries (%examples-doc-entries examples-doc)))
    (it "scripts/example-files.lisp registers every runnable example exactly once"
      (expect registered-example-files :to-equal filesystem-example-files))
    ;; Counting as well as looking each one up catches the reverse drift: an
    ;; example deleted from examples/ but left behind in the table.
    (it "docs/src/examples.md lists exactly as many examples as are registered"
      (expect (length doc-entries) :to-be (length registered-example-files)))
    (dolist (example registered-example-files)
      (let ((summary (cl-user::example-summary example)))
        (it (format nil "~A is documented with a matching summary" example)
          (let ((entry (assoc example doc-entries :test #'string=)))
            (expect entry)
            (expect (cdr entry) :to-equal summary)))))))

(describe "development command docs (docs/src/development.md)"
  (let ((development-doc (%doc-string "docs/src/development.md")))
    (dolist (command +expected-development-commands+)
      (it (format nil "~A is documented" command)
        (expect (%snippet-contains-p development-doc command))))))

(describe "README.md Quick Start"
  (let* ((readme (%doc-string "README.md"))
         (quick-start-snippets (%section-block-bodies readme "## Quick Start" "lisp")))
    ;; The README is the entry point, so it gets exactly one runnable example.
    ;; More than one means it is drifting back into being the manual.
    (it "contains exactly one Lisp snippet"
      (expect (length quick-start-snippets) :to-be 1))
    (it "the snippet includes every expected fragment"
      (dolist (fragment +expected-quick-start-fragments+)
        (expect (%snippet-contains-p (first quick-start-snippets) fragment))))))

(describe "docs/src/input-decoding.md examples"
  ;; Matched against any Lisp block on the page rather than a fixed position,
  ;; so reordering or adding examples does not break the check.
  (let ((snippets (%language-block-bodies (%doc-string "docs/src/input-decoding.md") "lisp")))
    (it "shows the streaming decoder example"
      (expect (%some-snippet-contains-all-p snippets +expected-streaming-fragments+)))
    (it "shows the bracketed-paste example"
      (expect (%some-snippet-contains-all-p snippets +expected-paste-fragments+)))))
