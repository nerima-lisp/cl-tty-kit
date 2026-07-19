(require :asdf)
(require :sb-cover)

;; LOAD and the CL-TTY-KIT/BOOTSTRAP reference below must be separate
;; top-level forms: a single EVAL-WHEN form is read in full -- including the
;; CL-TTY-KIT/BOOTSTRAP:LOAD-SUPPORT-FILES symbol -- before any of it runs, so
;; the reader would hit that package before LOAD had a chance to define it.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (proclaim '(optimize sb-cover:store-coverage-data)))

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(cl-tty-kit/bootstrap:load-support-files)

;; CL-TTY-KIT/TEST is loaded at runtime by LOAD-TEST-SYSTEM below, inside the
;; same top-level LET* that goes on to call RUN-TESTS -- but the reader reads
;; that whole LET* before any of it runs, so a direct
;; CL-TTY-KIT/TEST:RUN-TESTS reference would hit a nonexistent package at read
;; time. Look the symbol up by name instead, deferring resolution to runtime.
(defun call-exported-function (package-name symbol-name &rest arguments)
  (let* ((package (or (find-package package-name)
                      (error "Package ~A is not available." package-name)))
         (symbol (multiple-value-bind (symbol status)
                     (find-symbol symbol-name package)
                   (unless (eq status :external)
                     (error "Symbol ~A is not exported from ~A." symbol-name package-name))
                   symbol)))
    (apply (symbol-function symbol) arguments)))

(defparameter *coverage-timeout-seconds* 120)

(defmacro with-coverage-timeout ((label) &body body)
  `(handler-case
       (sb-ext:with-timeout *coverage-timeout-seconds*
         ,@body)
     (sb-ext:timeout ()
       (error "~A timed out after ~D seconds"
              ,label
              *coverage-timeout-seconds*))))

(defun coverage-entry-count ()
  "Return the number of SB-COVER instrumentation entries recorded so far, or 0
if this SBCL build keeps that data somewhere other than SB-INT:*CODE-COVERAGE-INFO*.
This is a progress diagnostic only; SB-COVER:REPORT below does not depend on it,
so an unresolvable symbol here degrades the log output, not the coverage report."
  (let ((variable (find-symbol "*CODE-COVERAGE-INFO*" "SB-INT")))
    (if (and variable (boundp variable))
        (hash-table-count (car (symbol-value variable)))
        0)))

(defun canonical-directory (path)
  (uiop:ensure-directory-pathname (truename path)))

(defun source-file-covered-p (path project-prefix)
  (and (search project-prefix path)
       (search "/src/" path)
       (probe-file path)))

(defun run-examples ()
  (dolist (file (cl-user::example-script-files))
    (format t "~&[RUN] ~A~%" file)
    (finish-output)
    (cl-tty-kit/bootstrap:run-example-file file)))

(let* ((scripts-dir (uiop:pathname-directory-pathname *load-truename*))
       (project-root (canonical-directory (merge-pathnames #P"../" scripts-dir)))
       (coverage-dir (merge-pathnames #P"coverage/" project-root))
       (project-prefix (namestring project-root)))
  (ensure-directories-exist coverage-dir)
  (sb-cover:clear-coverage)
  (format t "~&[COVERAGE] instrumented load~%")
  (finish-output)
  (with-coverage-timeout ("instrumented load")
    (cl-tty-kit/bootstrap:load-core-system))
  (format t "~&[COVERAGE] entries after load: ~D~%" (coverage-entry-count))
  (format t "~&[COVERAGE] tests~%")
  (finish-output)
  (with-coverage-timeout ("coverage tests")
    (cl-tty-kit/bootstrap:load-test-system)
    (call-exported-function "CL-TTY-KIT/TEST" "RUN-TESTS"))
  (format t "~&[COVERAGE] entries after tests: ~D~%" (coverage-entry-count))
  (format t "~&[COVERAGE] examples~%")
  (finish-output)
  (with-coverage-timeout ("coverage examples")
    (run-examples))
  (format t "~&[COVERAGE] entries after examples: ~D~%" (coverage-entry-count))
  (format t "~&[COVERAGE] report -> ~A~%" coverage-dir)
  (finish-output)
  (sb-cover:report coverage-dir
                   :if-matches (lambda (path)
                                 (source-file-covered-p path project-prefix))))
