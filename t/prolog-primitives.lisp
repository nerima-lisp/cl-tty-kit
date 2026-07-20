(in-package #:cl-tty-kit/test)

(defun test-prolog-primitives ()
  (do-test-case-bind (case +prolog-primitive-cases+
                           (predicate goal expected description))
    (is-equal expected
              (funcall predicate (%genealogy-db) goal)
              description))
  (let ((db (%genealogy-db)))
    (signals (error condition)
        (tty-prolog:solutions db '(tty-prolog:findall ?x (parent ?x ?y)))
      (is (search "Primitive FINDALL expects 3 arguments"
                  (princ-to-string condition))))
    (signals (error condition)
        (tty-prolog:solutions db '(= ?x))
      (is (search "Primitive = expects 2 arguments"
                  (princ-to-string condition))))
    (signals (error condition)
        (tty-prolog:solutions db '(tty-prolog:call (parent abraham isaac) extra))
      (is (search "Primitive CALL expects 1 argument"
                  (princ-to-string condition))))
    (signals (error condition)
        (tty-prolog:solutions db '(tty-prolog:true extra))
      (is (search "Primitive TRUE expects 0 arguments"
                  (princ-to-string condition)))))
  (signals (error condition)
      (tty-prolog:solutions
       (%many-solutions-db)
       '(tty-prolog:findall ?x (value ?x) ?result)
       '?result
       :max-results 2)
    (is (search "result limit" (princ-to-string condition)))))
