(require :asdf)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package '#:cl-tty-kit/test)
    (defpackage #:cl-tty-kit/test
      (:use #:cl #:uiop #:cl-tty-kit)
      (:export #:run-tests))))

(in-package #:cl-tty-kit/test)
