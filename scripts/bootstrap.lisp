(require :asdf)

(defpackage #:cl-tty-kit/bootstrap (:use #:cl)
  (:export
    #:project-root
    #:project-pathname
    #:load-project-file
    #:load-core-system
    #:load-support-files
    #:load-test-system
    #:load-example-file
    #:run-example-file
    #:call-exported-function
    #:with-script-timeout))

(in-package #:cl-tty-kit/bootstrap)

(defparameter *project-root* (uiop:ensure-directory-pathname
    (truename
      (merge-pathnames #P"../" (uiop:pathname-directory-pathname *load-truename*)))))

;; Register the local definition directly so ASDF need not scan every source
;; registry before a project script can load the core system.
(progn
  (pushnew *project-root* asdf:*central-registry* :test #'equal)
  (load (merge-pathnames #P"cl-tty-kit.asd" *project-root*)))

(defparameter *support-source-files* '("scripts/example-files.lisp"))

(defparameter *core-loaded-p* nil)

(defparameter *support-loaded-p* nil)

(defparameter *test-loaded-p* nil)

(defun project-root ()
  *project-root*)

(defun project-pathname (relative-pathname)
  (merge-pathnames relative-pathname *project-root*))

(defun load-project-file (relative-pathname)
  (load (project-pathname relative-pathname)))

(defun call-exported-function (package-name symbol-name &rest arguments)
  (let* ((package
        (or
          (find-package package-name)
          (error "Package ~A is not available." package-name)))
         (symbol
        (multiple-value-bind (symbol status) (find-symbol symbol-name package)
          (unless (eq status :external)
            (error "Symbol ~A is not exported from ~A." symbol-name package-name))
          symbol)))
    (apply (symbol-function symbol) arguments)))

;; Every script entry point (run-tests.lisp, scripts/verify.lisp,
;; scripts/coverage.lisp, scripts/examples.lisp,
;; scripts/source-registry-smoke.lisp) bounds its long-running steps so a
;; hang fails the build with the name of the step that stopped making
;; progress, rather than sitting until the CI job's own timeout reports only
;; "the job took 30 minutes". This was five near-identical
;; defparameter+defmacro pairs, one per script, differing only in the
;; timeout duration; SECONDS is now a per-call argument instead of a
;; per-file special variable.
(defmacro with-script-timeout ((label seconds) &body body)
  `(handler-case (sb-ext:with-timeout ,seconds ,@body)
     (sb-ext:timeout ()
       (error "~A timed out after ~D seconds" ,label ,seconds))))

(defun load-core-system (&key force)
  (when force
    (setf *core-loaded-p* nil))
  (unless *core-loaded-p*
    (asdf:load-system :cl-tty-kit :force force)
    (setf *core-loaded-p* t))
  t)

(defun load-support-files ()
  (unless *support-loaded-p*
    (dolist (file *support-source-files*)
      (load-project-file file))
    (setf *support-loaded-p* t))
  t)

(defun load-test-system (&key force)
  (when force
    (setf *test-loaded-p* nil))
  (unless *test-loaded-p*
    (asdf:load-system :cl-tty-kit/test :force force)
    (setf *test-loaded-p* t))
  t)

(defun load-example-file (file)
  (load-project-file file))

(defun run-example-file (file)
  (load-core-system)
  (load-support-files)
  (let ((cl-user::*cl-tty-kit-run-example-on-load* t))
    (declare (special cl-user::*cl-tty-kit-run-example-on-load*))
    (load-example-file file)))
