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
  '((tty-prolog:provable-p
      (ancestor abraham joseph)
      t
      "provable-p reports a reachable relation")
    (%not-provable-p
     (ancestor joseph abraham)
     t
     "provable-p reports an unreachable relation")
    (%solve-variable
      (= ?x bound)
      (bound)
      "the = primitive unifies its arguments")
    (%solve-parent
     (and (parent ?p jacob) (not (parent ?p joseph)))
     (isaac)
     "negation as failure filters out joseph's parent")
    (%solve-variable
     (or (parent isaac ?x) (parent jacob ?x))
     (jacob joseph)
     "disjunction enumerates the solutions of each branch in order")
    (%solve-variable
     (tty-prolog:call (ancestor abraham ?x))
     (isaac jacob joseph)
     "call/1 proves a goal term like an ordinary relation")
    (%solve-result
     (tty-prolog:findall ?a (ancestor ?a joseph) ?result)
     ((jacob abraham isaac))
     "findall/3 aggregates every solution into a single list in proof order")
    (%solve-result
     (tty-prolog:findall ?x (parent joseph ?x) ?result)
     (())
     "findall/3 yields the empty list when the goal has no proof")
    (%solve-variable
     (tty-prolog:call ?g)
     ()
     "call/1 fails gracefully on an unbound goal instead of crashing")
    (%solve-result
     (tty-prolog:findall ?x ?goal ?result)
     (())
     "findall/3 tolerates an unbound goal, collecting nothing")))

(defparameter +prolog-db-error-cases+
  '((primitive-clause
     "cannot take clauses"
     "primitive relations reject clauses")
    (clause-primitive
     "cannot become primitive"
     "relations with clauses reject primitives")
    (invalid-db
     "Expected a clause database"
     "add-clause rejects non-database inputs")
    (empty-clause
     "Clause must contain a head goal"
     "add-clause rejects empty clauses")
    (dotted-clause
     "Clause must be a proper list"
     "add-clause rejects dotted clauses")
    (variable-relation
     "Clause head must be a non-empty proper list"
     "add-clause rejects variable relation symbols")
    (invalid-primitive-relation
     "Primitive relation must be a non-variable symbol"
     "add-primitive rejects variable relation symbols")
    (invalid-primitive-function
     "Primitive implementation must be a function"
     "add-primitive rejects non-function implementations")))
