(in-package #:cl-tty-kit/test)

;;; Shared prolog test data and helpers. Keeping this file declarative makes the
;;; actual test files small and lets the suite enumerate behaviors one by one.
;;;
;;; AND/OR/NOT/= are ordinary Common Lisp symbols inherited from #:CL, so they
;;; dispatch to nerima-lisp/cl-prolog-kit's builtins from any package without
;;; qualification. CALL/FINDALL/TRUE/FAIL are cl-prolog-kit-specific exports with no
;;; CL equivalent, so a bare (unqualified) symbol of that name read in this file
;;; is a different symbol than CL-PROLOG-KIT:CALL and the engine reports the goal as
;;; an undefined procedure -- these four are written CL-PROLOG-KIT:CALL etc.
;;; throughout.

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
  '((cl-prolog-kit:prolog-succeeds-p
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
     (cl-prolog-kit:call (ancestor abraham ?x))
     (isaac jacob joseph)
     "call/1 proves a goal term like an ordinary relation")
    (%solve-result
     (cl-prolog-kit:findall ?a (ancestor ?a joseph) ?result)
     ((jacob abraham isaac))
     "findall/3 aggregates every solution into a single list in proof order")
    (%solve-result
     (cl-prolog-kit:findall ?x (parent joseph ?x) ?result)
     (())
     "findall/3 yields the empty list when the goal has no proof")
    (%not-provable-p
     (cl-prolog-kit:fail)
     t
     "fail/0 never succeeds")
    (%not-provable-p
     (not (parent abraham isaac))
     t
     "negation fails when its goal already has a proof")
    (%not-provable-p
     (= abraham isaac)
     t
     "the = primitive fails when its arguments don't unify")
    (cl-prolog-kit:prolog-succeeds-p
     (cl-prolog-kit:true)
     t
     "true/0 always succeeds")
    (%not-provable-p
     (cl-prolog-kit:findall ?x (parent abraham ?x) (mismatch))
     t
     "findall/3 fails when RESULT doesn't unify with the collected items")))
