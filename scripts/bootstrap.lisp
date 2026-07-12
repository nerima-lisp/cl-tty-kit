(require :asdf)

(defpackage #:cl-tty-kit/bootstrap
  (:use #:cl)
  (:export #:project-root
           #:project-pathname
           #:load-project-file
           #:load-core-system
           #:load-support-files
           #:load-test-system
           #:load-example-file
           #:run-example-file))

(in-package #:cl-tty-kit/bootstrap)

(defparameter *project-root*
  (uiop:ensure-directory-pathname
   (truename
    (merge-pathnames #P"../"
                     (uiop:pathname-directory-pathname *load-truename*)))))

(defparameter *support-source-files*
  '("scripts/example-files.lisp"))

(defparameter *core-loaded-p* nil)
(defparameter *support-loaded-p* nil)
(defparameter *test-loaded-p* nil)

(defun project-root ()
  *project-root*)

(defun project-pathname (relative-pathname)
  (merge-pathnames relative-pathname *project-root*))

(defun load-project-file (relative-pathname)
  (load (project-pathname relative-pathname)))

(defun load-core-system ()
  (unless *core-loaded-p*
    (asdf:load-system :cl-tty-kit)
    (setf *core-loaded-p* t))
  t)

(defun load-support-files ()
  (unless *support-loaded-p*
    (dolist (file *support-source-files*)
      (load-project-file file))
    (setf *support-loaded-p* t))
  t)

(defun load-test-system ()
  (unless *test-loaded-p*
    (asdf:load-system :cl-tty-kit/test)
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
