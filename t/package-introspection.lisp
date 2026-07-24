(in-package #:cl-tty-kit/test)

(defun %project-defsystem-form (system-name)
  (with-open-file (stream (cl-tty-kit/bootstrap:project-pathname "cl-tty-kit.asd")
                          :direction :input)
    (loop for form = (read stream nil :eof)
          until (eq form :eof)
          when (and (consp form)
                    (string= "DEFSYSTEM" (symbol-name (first form)))
                    (string= (string system-name)
                             (string (second form))))
            do (return form)
          finally (error "System definition ~S not found." system-name))))

(defun %system-definition-metadata-plist (system-name)
  (let ((definition (%project-defsystem-form system-name)))
    (loop with metadata-keys = '(:description
                                 :author
                                 :maintainer
                                 :license
                                 :homepage
                                 :bug-tracker
                                 :source-control
                                 :version)
          for (key value) on (cddr definition) by #'cddr
          when (member key metadata-keys)
            append (list key value))))

(defun %package-external-symbol-names (pkg)
  (let ((symbols '()))
    (do-external-symbols (symbol pkg)
      (push (symbol-name symbol) symbols))
    (sort symbols #'string<)))

(defun %expected-system-metadata-cases ()
  (mapcar (lambda (entry)
            (list (car entry) (cdr entry)))
          +expected-system-metadata+))

(defun %assert-system-metadata-case (system-metadata key expected)
  (assert (string= (getf system-metadata key) expected) ()
          "ASDF metadata ~S should be ~S but was ~S"
          key
          expected
          (getf system-metadata key)))

(defun %assert-external-symbols (pkg symbol-names)
  (dolist (symbol-name symbol-names)
    (multiple-value-bind (symbol status) (find-symbol symbol-name pkg)
      (assert symbol () "~A should be present" symbol-name)
      (assert (eq :external status) () "~A should be external" symbol-name))))

(defun %assert-non-empty-public-documentation (pkg)
  (labels ((non-empty-doc-p (symbol kind)
             (let ((doc (documentation symbol kind)))
               (and (stringp doc)
                    (> (length doc) 0)))))
    (do-external-symbols (symbol pkg)
      (when (fboundp symbol)
        (assert (non-empty-doc-p symbol 'function) ()
                "~A should have function documentation" symbol))
      (when (find-class symbol nil)
        (assert (non-empty-doc-p symbol 'type) ()
                "~A should have type documentation" symbol)))))

(defun test-utils ()
  (assert (null (cl-tty-kit::string-empty-p "x")))
  (assert (cl-tty-kit::string-empty-p ""))
  (assert (cl-tty-kit::string-empty-p nil))
  (assert (null (cl-tty-kit::string-empty-p 42)))
  (assert (equal '(:x) (cl-tty-kit::ensure-list* :x)))
  (assert (equal '(:x :y) (cl-tty-kit::ensure-list* '(:x :y))))
  (assert (= 3 (cl-tty-kit::clamp 3 0 9)))
  (assert (= 0 (cl-tty-kit::clamp -1 0 9)))
  (assert (= 9 (cl-tty-kit::clamp 10 0 9)))
  (assert (= 9 (cl-tty-kit::clamp 5 9 3)))
  (assert (equal '(:alt :bogus :control :shift)
                 (cl-tty-kit::normalize-modifiers '(:shift :alt :control :shift :bogus 1))))
  (assert (equal '(:shift) (cl-tty-kit::modifiers-from-csi-number 2)))
  (assert (equal '(:alt) (cl-tty-kit::modifiers-from-csi-number 3)))
  (assert (equal '(:control) (cl-tty-kit::modifiers-from-csi-number 5)))
  (assert (equal '(:alt :control :shift) (cl-tty-kit::modifiers-from-csi-number 8)))
  t)

(defun test-char-width-api ()
  (let ((combining-string (coerce (list #\e (code-char #x0301)) 'string)))
    (assert (= 1 (char-width #\A)))
    (assert (= 0 (char-width #\Newline)))
    (assert (= 0 (char-width (code-char #x0301))))
    (assert (= 2 (char-width #x65E5)))
    (assert (= 2 (char-width (code-char #x1F600))))
    (assert (= 2 (string-width "ab")))
    (assert (= 4 (string-width "a日b")))
    (assert (= 1 (string-width combining-string)))
    (assert (= 3 (string-width "ab日" :start 1 :end 3))))
  t)

(defun %test-package-metadata (system-metadata)
  (do-test-case-bind (entry-case (%expected-system-metadata-cases) (key expected))
    (%assert-system-metadata-case system-metadata key expected)))

(defun %test-package-exports (pkg external-symbols readme-api-symbols)
  (%assert-external-symbols pkg +expected-external-symbols+)
  (assert (equal external-symbols readme-api-symbols) ()
          "README.md API Overview should match package exports exactly.~%Exports: ~S~%README: ~S"
          external-symbols
          readme-api-symbols))
