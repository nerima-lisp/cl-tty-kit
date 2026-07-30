(in-package #:cl-tty-kit/test)

;;; cl-prolog's rulebase is an immutable value by default (see the Rule DSL
;;; docs on EXTEND-RULEBASE) rather than the retired hand-rolled engine's
;;; mutable clause-db, so the invariants worth checking here are different:
;;; functional extension leaves the base untouched, and an undefined relation
;;; signals a catchable ISO condition instead of silently failing.

(describe "extend-rulebase"
  (it "leaves the base rulebase unaffected"
    (let* ((base (cl-prolog:prolog ((color apple red)))))
      (cl-prolog:extend-rulebase base ((color lime green)))
      (expect (mapcar (lambda (solution) (cl-prolog:solution-binding '?color solution))
                      (cl-prolog:query-prolog base '(color apple ?color)))
              :to-equal '(red))))
  (it "sees its own additional clauses"
    (let* ((base (cl-prolog:prolog ((color apple red))))
           (extended (cl-prolog:extend-rulebase base ((color lime green)))))
      (expect (mapcar (lambda (solution) (cl-prolog:solution-binding '?color solution))
                      (cl-prolog:query-prolog extended '(color lime ?color)))
              :to-equal '(green))))
  (it "also sees the base's clauses"
    (let* ((base (cl-prolog:prolog ((color apple red))))
           (extended (cl-prolog:extend-rulebase base ((color lime green)))))
      (expect (mapcar (lambda (solution) (cl-prolog:solution-binding '?color solution))
                      (cl-prolog:query-prolog extended '(color apple ?color)))
              :to-equal '(red)))))

(describe "an undefined relation"
  (it "signals a catchable prolog-existence-error instead of failing silently"
    (expect (lambda () (cl-prolog:query-prolog (%genealogy-db) '(no-such-relation abraham)))
            :to-throw 'cl-prolog:prolog-existence-error)))
