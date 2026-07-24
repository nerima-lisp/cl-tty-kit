(defpackage #:cl-tty-kit/weave-mutation-tests
  (:use #:cl)
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave
                #:expect #:it
                #:run-mutations #:assert-mutation-score
                #:run-all)
  (:export #:run-tests))

(in-package #:cl-tty-kit/weave-mutation-tests)

;;; Mutation testing: takeokunn/cl-weave systematically mutates a pure
;;; function's body (flipping arithmetic/comparison operators, boolean
;;; literals, and conditional branches) and re-checks each variant against the
;;; same case battery a unit test would use. A mutation the battery fails to
;;; notice ("survived") marks a gap SB-COVER's line/branch coverage cannot
;;; see: coverage proves a line executed, not that a wrong result there would
;;; be caught. The body is read live from the SRC/ source file on every run
;;; (never copied into this file), so there is nothing here to fall out of
;;; sync with the real implementation.

(defun %read-defun-forms (pathname)
  "Return every top-level DEFUN form read from PATHNAME.
Read with *PACKAGE* bound to CL-TTY-KIT so every symbol in the returned forms
-- the function name, parameters, and any CL-TTY-KIT function it calls --
resolves to the same symbol the real, loaded definition uses."
  (let ((*package* (find-package "CL-TTY-KIT")))
    (with-open-file (stream pathname)
      (loop for form = (read stream nil :eof)
            until (eq form :eof)
            when (and (consp form) (eq (first form) 'cl:defun))
              collect form))))

(defun %find-defun-form (relative-path name)
  "Read RELATIVE-PATH's DEFUN named NAME, matching by symbol name (not
identity) since READ interns the file's symbols into *PACKAGE* at read time,
not the target file's own package."
  (let ((pathname (asdf:system-relative-pathname :cl-tty-kit relative-path))
        (target-name (string name)))
    (or (find target-name (%read-defun-forms pathname)
              :key (lambda (form) (string (second form)))
              :test #'string=)
        (error "No DEFUN ~A found in ~A." name pathname))))

(defun %defun-lambda-list (defun-form)
  (third defun-form))

(defun %defun-body-form (defun-form)
  "Return DEFUN-FORM's body as a single form, skipping a leading docstring and
wrapping multiple body forms in a PROGN."
  (let ((body (cdddr defun-form)))
    (when (and (stringp (first body)) (rest body))
      (setf body (rest body)))
    (if (rest body) (cons 'cl:progn body) (first body))))

(defun %eval-with-bindings (form lambda-list argument-forms)
  (eval `(let ,(mapcar #'list lambda-list argument-forms) ,form)))

(defun %mutation-oracle (body lambda-list cases)
  "Return a CL-WEAVE:RUN-MUTATIONS test function asserting MUTATED-FORM still
satisfies every (ARGUMENT-FORMS . EXPECTED) entry in CASES. A mismatch signals
ASSERTION-FAILURE via EXPECT, which RUN-MUTATIONS reports as a killed
mutation; matching every case leaves the mutation looking survived."
  (declare (ignore body))
  (lambda (mutated-form mutation)
    (declare (ignore mutation))
    (dolist (case cases t)
      (destructuring-bind (argument-forms expected) case
        (expect (%eval-with-bindings mutated-form lambda-list argument-forms)
                :to-equal expected)))))

(defun %assert-full-mutation-kill (relative-path name cases)
  "Mutate the DEFUN named NAME in RELATIVE-PATH and assert CASES kills every
mutation (a mutation score of 1.0), i.e. the case battery is strong enough to
notice every one-operator change to the real implementation."
  (let* ((defun-form (%find-defun-form relative-path name))
         (lambda-list (%defun-lambda-list defun-form))
         (body (%defun-body-form defun-form))
         (results (run-mutations body (%mutation-oracle body lambda-list cases))))
    (assert-mutation-score results 1.0)))

(describe "src/clamp.lisp: CLAMP mutation coverage"
  (it "the case battery matches the live function on every case"
    (dolist (case '(((5 0 10) 5) ((-5 0 10) 0) ((15 0 10) 10)
                     ((5 10 0) 10) ((7 7 7) 7) ((0 -3 3) 0)))
      (destructuring-bind ((value min max) expected) case
        (expect (cl-tty-kit::clamp value min max) :to-equal expected))))
  (it "every mutation of CLAMP's body is killed by the case battery"
    (%assert-full-mutation-kill
     "src/clamp.lisp" 'cl-tty-kit::clamp
     '(((5 0 10) 5) ((-5 0 10) 0) ((15 0 10) 10)
       ((5 10 0) 10) ((7 7 7) 7) ((0 -3 3) 0)))))

(describe "src/rect.lisp: RECT-RIGHT and RECT-BOTTOM mutation coverage"
  (it "every mutation of RECT-RIGHT's body is killed by the case battery"
    (%assert-full-mutation-kill
     "src/rect.lisp" 'cl-tty-kit::rect-right
     '((((cl-tty-kit:make-rect :x 3 :width 4)) 7)
       (((cl-tty-kit:make-rect :x 0 :width 0)) 0)
       (((cl-tty-kit:make-rect :x 10 :width 5)) 15))))
  (it "every mutation of RECT-BOTTOM's body is killed by the case battery"
    (%assert-full-mutation-kill
     "src/rect.lisp" 'cl-tty-kit::rect-bottom
     '((((cl-tty-kit:make-rect :y 3 :height 4)) 7)
       (((cl-tty-kit:make-rect :y 0 :height 0)) 0)
       (((cl-tty-kit:make-rect :y 10 :height 5)) 15)))))

(defun run-tests ()
  "Run every DESCRIBE/IT block registered above and return true iff all of
them passed."
  (run-all :reporter :spec))
