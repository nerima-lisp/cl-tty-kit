(in-package #:cl-tty-kit/test)

(defun test-prolog-queries ()
  (do-test-case-bind (case +prolog-query-cases+
                           (goal template expected description &key set-p))
    (%check-query (%genealogy-db) goal template expected description
                  :set-p set-p)))
