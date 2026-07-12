(in-package #:cl-tty-kit/test)

(defun test-prolog-primitives ()
  (do-test-case-bind (case +prolog-primitive-cases+
                           (predicate goal expected description))
    (is-equal expected
              (funcall predicate (%genealogy-db) goal)
              description)))
