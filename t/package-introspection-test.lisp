(in-package #:cl-tty-kit/test)

(defun %project-defsystem-form (system-name)
  (with-open-file (stream (cl-tty-kit/bootstrap:project-pathname "cl-tty-kit.asd")
                          :direction :input)
    (loop for form = (read stream nil :eof)
          until (eq form :eof)
          when (and (consp form)
                    (string= "DEFSYSTEM" (symbol-name (first form)))
                    ;; STRING-EQUAL, not STRING=: system names in the .asd are
                    ;; now strings ("cl-tty-kit"), while callers pass keywords
                    ;; (:cl-tty-kit) whose STRING is upcased by the reader.
                    ;; Comparing case-sensitively would silently match nothing
                    ;; and fall through to the error below.
                    (string-equal (string system-name)
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

(defun %non-empty-doc-p (symbol kind)
  (let ((doc (documentation symbol kind)))
    (and (stringp doc) (plusp (length doc)))))

(describe "internal utility functions"
  (it "string-empty-p"
    (expect (cl-tty-kit::string-empty-p "x") :to-be-falsy)
    (expect (cl-tty-kit::string-empty-p "") :to-be-truthy)
    (expect (cl-tty-kit::string-empty-p nil) :to-be-truthy)
    (expect (cl-tty-kit::string-empty-p 42) :to-be-falsy))
  (it "ensure-list*"
    (expect (cl-tty-kit::ensure-list* :x) :to-equal '(:x))
    (expect (cl-tty-kit::ensure-list* '(:x :y)) :to-equal '(:x :y)))
  (it "clamp"
    (expect (cl-tty-kit::clamp 3 0 9) :to-be 3)
    (expect (cl-tty-kit::clamp -1 0 9) :to-be 0)
    (expect (cl-tty-kit::clamp 10 0 9) :to-be 9)
    (expect (cl-tty-kit::clamp 5 9 3) :to-be 9))
  (it "normalize-modifiers"
    (expect (cl-tty-kit::normalize-modifiers '(:shift :alt :control :shift :bogus 1))
            :to-equal '(:alt :bogus :control :shift)))
  (it "modifiers-from-csi-number"
    (expect (cl-tty-kit::modifiers-from-csi-number 2) :to-equal '(:shift))
    (expect (cl-tty-kit::modifiers-from-csi-number 3) :to-equal '(:alt))
    (expect (cl-tty-kit::modifiers-from-csi-number 5) :to-equal '(:control))
    (expect (cl-tty-kit::modifiers-from-csi-number 8) :to-equal '(:alt :control :shift))))

(describe "char-width and string-width, public API smoke test"
  (it "covers combining marks, wide glyphs, and substring ranges"
    (let ((combining-string (coerce (list #\e (code-char #x0301)) 'string)))
      (expect (char-width #\A) :to-be 1)
      (expect (char-width #\Newline) :to-be 0)
      (expect (char-width (code-char #x0301)) :to-be 0)
      (expect (char-width #x65E5) :to-be 2)
      (expect (char-width (code-char #x1F600)) :to-be 2)
      (expect (string-width "ab") :to-be 2)
      (expect (string-width "a日b") :to-be 4)
      (expect (string-width combining-string) :to-be 1)
      (expect (string-width "ab日" :start 1 :end 3) :to-be 3))))

(describe "ASDF system metadata (cl-tty-kit.asd)"
  (let ((system-metadata (%system-definition-metadata-plist :cl-tty-kit)))
    (dolist (entry +expected-system-metadata+)
      (destructuring-bind (key . expected) entry
        (it (format nil "~(~A~) matches +expected-system-metadata+" key)
          (expect (getf system-metadata key) :to-equal expected))))))

(describe "package exports (cl-tty-kit)"
  (let ((pkg (find-package :cl-tty-kit)))
    (dolist (symbol-name +expected-external-symbols+)
      (it (format nil "~A is exported" symbol-name)
        (multiple-value-bind (symbol status) (find-symbol symbol-name pkg)
          (expect symbol)
          (expect status :to-be :external))))
    ;; Equality, not just containment. The export set used to be pinned by
    ;; README.md's API Overview, which the README could no longer carry once it
    ;; was capped at 150 lines. +expected-external-symbols+ takes over that role,
    ;; so adding or removing an export still has to be a deliberate edit to test
    ;; data rather than something that happens silently.
    (it "the export set matches +expected-external-symbols+ exactly"
      (expect (%package-external-symbol-names pkg)
              :to-equal (sort (copy-list +expected-external-symbols+) #'string<)))))

(describe "public API documentation"
  (let ((pkg (find-package :cl-tty-kit)))
    (it "every fbound external symbol has non-empty function documentation"
      (do-external-symbols (symbol pkg)
        (when (fboundp symbol)
          (expect (%non-empty-doc-p symbol 'function)))))
    (it "every external symbol naming a class has non-empty type documentation"
      (do-external-symbols (symbol pkg)
        (when (find-class symbol nil)
          (expect (%non-empty-doc-p symbol 'type)))))))
