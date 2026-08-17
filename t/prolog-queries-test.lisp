(in-package #:cl-tty-kit/test)

(describe "resolving a goal against a rulebase"
  (dolist (case +prolog-query-cases+)
    (destructuring-bind (goal template expected description &key set-p) case
      (it description
        (%check-query (%genealogy-db) goal template expected :set-p set-p))))
  ;; NOTE: unlike cl-tty-kit's retired hand-rolled engine, cl-prolog-kit does not
  ;; proactively guard against a directly self-referential (circular) host
  ;; goal term at the query level -- QUERY-PROLOG hangs rather than signaling,
  ;; so that case is intentionally not exercised here. Only pass well-formed,
  ;; finite goal terms to QUERY-PROLOG/PROLOG-SUCCEEDS-P.
  (it "signals prolog-depth-limit-exceeded on an infinite goal past max-depth"
    (let ((db (cl-prolog-kit:prolog ((loop ?x) (loop (s ?x))))))
      (expect (lambda () (cl-prolog-kit:query-prolog db '(loop ?x) :max-depth 5))
              :to-throw 'cl-prolog-kit:prolog-depth-limit-exceeded)))
  (it "signals invalid-max-depth-error with the offending value for a negative max-depth"
    (expect (lambda ()
              (cl-prolog-kit:prolog-succeeds-p (%genealogy-db) '(parent abraham isaac)
                                           :max-depth -1))
            :to-throw
            (lambda (condition)
              (and (typep condition 'cl-prolog-kit:invalid-max-depth-error)
                   (= -1 (cl-prolog-kit:invalid-max-depth-error-value condition))))))
  ;; Unlike the retired engine's hard "result limit" budget, cl-prolog-kit's :LIMIT
  ;; is a benign cap: querying for more solutions than exist under a :LIMIT
  ;; simply returns what was found, with no error.
  (it ":limit truncates instead of erroring"
    (expect (mapcar (lambda (solution) (cl-prolog-kit:solution-binding '?x solution))
                    (cl-prolog-kit:query-prolog (%many-solutions-db) '(value ?x) :limit 2))
            :to-equal '(one two)))
  (it "signals type-error with the offending value for a negative limit"
    (expect (lambda () (cl-prolog-kit:query-prolog (%many-solutions-db) '(value ?x) :limit -1))
            :to-throw
            (lambda (condition)
              (and (typep condition 'type-error)
                   (= -1 (type-error-datum condition)))))))
