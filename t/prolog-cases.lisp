(in-package #:cl-tty-kit/test)

;;; Shared prolog test data and helpers. Keeping this file declarative makes the
;;; actual test files small and lets the suite enumerate behaviors one by one.

(defparameter +prolog-query-cases+
  '(((parent isaac ?child) ?child (jacob)
     "direct facts unify their bound argument")
    ((ancestor abraham ?descendant) ?descendant
     (isaac jacob joseph)
     "recursive rules enumerate every descendant in order")
    ((ancestor ?a joseph) ?a (jacob isaac abraham)
     "resolution finds every ancestor regardless of search order"
     :set-p t)
    ((parent ?p jacob) ?p (isaac)
     "an unbound first argument is solved from the facts")
    ((parent joseph ?child) ?child ()
     "an unprovable goal yields no solutions")))

(defparameter +prolog-primitive-cases+
  '((#'tty-prolog:provable-p
      (ancestor abraham joseph)
      t
      "provable-p reports a reachable relation")
    (#'%not-provable-p
     (ancestor joseph abraham)
     t
     "provable-p reports an unreachable relation")
    (#'%solve-variable
      (= ?x bound)
      (bound)
      "the = primitive unifies its arguments")
    (#'%solve-parent
     (and (parent ?p jacob) (not (parent ?p joseph)))
     (isaac)
     "negation as failure filters out joseph's parent")))

(defparameter +prolog-db-error-cases+
  '((primitive-clause
     "cannot take clauses"
     "primitive relations reject clauses")
    (clause-primitive
     "cannot become primitive"
     "relations with clauses reject primitives")))
