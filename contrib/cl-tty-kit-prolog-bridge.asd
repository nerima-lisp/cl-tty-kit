;;;; Optional contrib system. NOT part of the core cl-tty-kit build or CI.
;;;;
;;;; It bridges cl-tty-kit's embedded logic engine to a full external ISO Prolog
;;;; through cl-prolog2 (latest Quicklisp release). Load it explicitly:
;;;;
;;;;   (ql:quickload :cl-tty-kit-prolog-bridge)
;;;;
;;;; `run-clause-db-query` additionally requires an ISO Prolog binary such as
;;;; swipl on PATH; the pure translation layer (`clause-db-rules`) does not.

(asdf:defsystem #:cl-tty-kit-prolog-bridge
  :description "Bridge cl-tty-kit's embedded clause database to an external ISO Prolog via cl-prolog2."
  :author "takeokunn"
  :license "MIT"
  :depends-on (#:cl-tty-kit #:cl-prolog2)
  :components ((:file "prolog-bridge")))
