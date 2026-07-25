(in-package #:cl-tty-kit/test)

;;; cl-prolog's rulebase is an immutable value by default (see the Rule DSL
;;; docs on EXTEND-RULEBASE) rather than the retired hand-rolled engine's
;;; mutable clause-db, so the invariants worth checking here are different:
;;; functional extension leaves the base untouched, and an undefined relation
;;; signals a catchable ISO condition instead of silently failing.

(defun test-prolog-db-invariants ()
  (let* ((base (cl-prolog:prolog ((color apple red))))
         (extended (cl-prolog:extend-rulebase base ((color lime green)))))
    (is-equal '(red)
              (mapcar (lambda (solution) (cl-prolog:solution-binding '?color solution))
                      (cl-prolog:query-prolog base '(color apple ?color)))
              "the base rulebase is unaffected by EXTEND-RULEBASE")
    (is-equal '(green)
              (mapcar (lambda (solution) (cl-prolog:solution-binding '?color solution))
                      (cl-prolog:query-prolog extended '(color lime ?color)))
              "the extended rulebase sees its own additional clauses")
    (is-equal '(red)
              (mapcar (lambda (solution) (cl-prolog:solution-binding '?color solution))
                      (cl-prolog:query-prolog extended '(color apple ?color)))
              "the extended rulebase also sees the base's clauses"))
  (signals (cl-prolog:prolog-existence-error condition)
      (cl-prolog:query-prolog (%genealogy-db) '(no-such-relation abraham))
    (is condition)))
