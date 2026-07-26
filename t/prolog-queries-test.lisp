(in-package #:cl-tty-kit/test)

(defun test-prolog-queries ()
  (do-test-case-bind (case +prolog-query-cases+
                           (goal template expected description &key set-p))
    (%check-query (%genealogy-db) goal template expected description
                  :set-p set-p))
  ;; NOTE: unlike cl-tty-kit's retired hand-rolled engine, cl-prolog does not
  ;; proactively guard against a directly self-referential (circular) host
  ;; goal term at the query level -- QUERY-PROLOG hangs rather than signaling,
  ;; so that case is intentionally not exercised here. Only pass well-formed,
  ;; finite goal terms to QUERY-PROLOG/PROLOG-SUCCEEDS-P.
  (let ((db (cl-prolog:prolog ((loop ?x) (loop (s ?x))))))
    (signals (cl-prolog:prolog-depth-limit-exceeded condition)
        (cl-prolog:query-prolog db '(loop ?x) :max-depth 5)
      (is condition)))
  (signals (cl-prolog:invalid-max-depth-error condition)
      (cl-prolog:prolog-succeeds-p (%genealogy-db) '(parent abraham isaac)
                                   :max-depth -1)
    (is (= -1 (cl-prolog:invalid-max-depth-error-value condition))))
  ;; Unlike the retired engine's hard "result limit" budget, cl-prolog's :LIMIT
  ;; is a benign cap: querying for more solutions than exist under a :LIMIT
  ;; simply returns what was found, with no error.
  (is-equal '(one two)
            (mapcar (lambda (solution) (cl-prolog:solution-binding '?x solution))
                    (cl-prolog:query-prolog (%many-solutions-db) '(value ?x)
                                            :limit 2))
            ":limit truncates instead of erroring")
  (signals (type-error condition)
      (cl-prolog:query-prolog (%many-solutions-db) '(value ?x) :limit -1)
    (is (= -1 (type-error-datum condition)))))
