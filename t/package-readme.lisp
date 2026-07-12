(in-package #:cl-tty-kit/test)

(defun %readme-example-entry-p (readme path)
  (search (format nil "- `~A`" path) readme))

(defun %readme-example-summary-entry-p (readme path summary)
  (search (format nil "- `~A`: ~A" path summary) readme))

(defun %readme-command-entry-p (readme command)
  (search command readme))

(defun %readme-fenced-blocks (readme)
  (let ((blocks '())
        (section nil)
        (in-block-p nil)
        (block-language nil)
        (block-lines '()))
    (with-input-from-string (stream readme)
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

(defun %readme-section-block-bodies (readme section language)
  (loop for block in (%readme-fenced-blocks readme)
        when (and (string= (getf block :section) section)
                  (string= (getf block :language) language))
          collect (getf block :body)))

(defun %readme-api-symbols (readme)
  (let ((symbols '())
        (in-api-overview-p nil))
    (with-input-from-string (stream readme)
      (loop for line = (read-line stream nil nil)
            while line
            do (cond
                 ((string= line "## API Overview")
                  (setf in-api-overview-p t))
                 ((and in-api-overview-p
                       (let ((section-start (search "## " line)))
                         (and section-start
                              (zerop section-start))))
                   (return))
                 ((and in-api-overview-p
                       (> (length line) 4)
                       (eql 0 (search "- `" line))
                       (char= #\` (char line (1- (length line)))))
                  (push (string-upcase (subseq line 3 (1- (length line))))
                        symbols)))))
    (nreverse symbols)))

(defun %snippet-contains-p (snippet fragment)
  (not (null (search fragment snippet))))

(defun %assert-fragments-present (snippet fragments message-template)
  (dolist (fragment fragments)
    (assert (%snippet-contains-p snippet fragment) ()
            message-template
            fragment)))

(defun %filesystem-example-script-files ()
  (let* ((project-root (cl-tty-kit/bootstrap:project-root))
         (example-paths (directory (merge-pathnames #P"examples/*.lisp" project-root))))
    (sort (loop for path in example-paths
                for relative = (enough-namestring path project-root)
                unless (string= relative "examples/bootstrap.lisp")
                  collect relative)
          #'string<)))

(defun %readme-example-cases (example-files)
  (mapcar (lambda (example)
            (list example (cl-user::example-summary example)))
          example-files))

(defun %readme-command-cases ()
  (mapcar #'list +expected-readme-commands+))

(defun %assert-readme-example-case (readme example summary)
  (assert (%readme-example-entry-p readme example) ()
          "~A should be listed in README.md Quick Start examples"
          example)
  (assert (%readme-example-summary-entry-p readme example summary) ()
          "~A should include its summary in README.md Quick Start examples"
          example))

(defun %assert-readme-command-case (readme command)
  (assert (%readme-command-entry-p readme command) ()
          "~A should be documented in README.md"
          command))

(defun %test-example-registration (readme registered-example-files filesystem-example-files)
  (assert (equal registered-example-files filesystem-example-files) ()
          "scripts/example-files.lisp should register every runnable example exactly once.~%Registered: ~S~%Filesystem: ~S"
          registered-example-files
          filesystem-example-files)
  (do-test-case-bind (example-case (%readme-example-cases registered-example-files)
                                    (example summary))
    (%assert-readme-example-case readme example summary)))

(defun %test-readme-command-docs (readme)
  (do-test-case-bind (command-case (%readme-command-cases) (command))
    (%assert-readme-command-case readme command)))

(defun %test-readme-snippets (quick-start-snippets input-snippets)
  (assert (= 1 (length quick-start-snippets)) ()
          "README.md should contain exactly one Quick Start Lisp snippet")
  (%assert-fragments-present
   (first quick-start-snippets)
   +expected-quick-start-fragments+
   "README.md Quick Start snippet should include ~S")
  (assert (>= (length input-snippets) 2) ()
          "README.md should contain at least two Core Concepts Lisp snippets")
  (%assert-fragments-present
   (first input-snippets)
   +expected-streaming-readme-fragments+
   "README.md streaming decoder snippet should include ~S")
  (%assert-fragments-present
   (second input-snippets)
   +expected-paste-readme-fragments+
   "README.md bracketed paste snippet should include ~S"))

(defun test-package ()
  (test-utils)
  (test-char-width-api)
  (let* ((pkg (find-package :cl-tty-kit))
         (system-metadata (%system-definition-metadata-plist :cl-tty-kit))
         (readme (uiop:read-file-string
                  (cl-tty-kit/bootstrap:project-pathname "README.md")))
         (quick-start-snippets (%readme-section-block-bodies
                                readme
                                "## Quick Start"
                                "lisp"))
         (input-snippets (%readme-section-block-bodies
                          readme
                          "## Core Concepts"
                          "lisp"))
         (readme-api-symbols (sort (%readme-api-symbols readme) #'string<))
         (external-symbols (%package-external-symbol-names pkg))
         (registered-example-files (sort (copy-list (cl-user::example-script-files))
                                         #'string<))
         (filesystem-example-files (%filesystem-example-script-files)))
    (%test-package-metadata system-metadata)
    (%test-package-exports pkg external-symbols readme-api-symbols)
    (%test-example-registration readme
                                registered-example-files
                                filesystem-example-files)
    (%test-readme-command-docs readme)
    (%test-readme-snippets quick-start-snippets input-snippets)
    (%assert-non-empty-public-documentation pkg)
    t))
