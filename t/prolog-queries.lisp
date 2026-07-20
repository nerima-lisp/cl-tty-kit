(in-package #:cl-tty-kit/test)

(defun test-prolog-queries ()
  (do-test-case-bind (case +prolog-query-cases+
                           (goal template expected description &key set-p))
    (%check-query (%genealogy-db) goal template expected description
                  :set-p set-p))
  (let ((goal (list 'parent 'abraham 'isaac)))
    (setf (rest goal) goal)
    (signals (error condition)
        (tty-prolog:solutions (%genealogy-db) goal)
      (is (search "circular term" (princ-to-string condition)))))
  (let ((db (tty-prolog:make-clause-db)))
    (tty-prolog:add-clause db '((loop ?x) (loop (s ?x))))
    (signals (error condition)
        (tty-prolog:solutions db '(loop ?x) '?x :max-steps 5)
      (is (search "step budget" (princ-to-string condition)))))
  (signals (error condition)
      (tty-prolog:provable-p (%genealogy-db) '(parent abraham isaac)
                             :max-steps -1)
    (is (search "max-steps" (princ-to-string condition))))
  (signals (error condition)
      (tty-prolog:solutions (%many-solutions-db) '(value ?x) '?x
                            :max-results 2)
    (is (search "result limit" (princ-to-string condition))))
  (signals (error condition)
      (tty-prolog:solutions (%many-solutions-db) '(value ?x) '?x
                            :max-results -1)
    (is (search "max-results" (princ-to-string condition)))))
