(in-package #:cl-tty-kit/prolog)

;;; --------------------------------------------------------------------------
;;; Primitive relations
;;; --------------------------------------------------------------------------

(defun %assert-primitive-arity (relation args arity)
  (unless (and (%proper-list-p args) (= (length args) arity))
    (error "Primitive ~A expects ~D argument~:P, got ~S."
           (symbol-name relation)
           arity
           args))
  args)

(define-primitive %primitive-not (db args bindings state succeed fail)
  "Negation as failure: succeed when the single goal argument has no proof."
  (%assert-primitive-arity 'not args 1)
  (if (not (%proof-exists-p db
                            (%subst-bindings bindings (first args))
                            bindings
                            state))
      (funcall succeed bindings fail)
      (funcall fail)))

(define-primitive %primitive-and (db args bindings state succeed fail)
  "The relational `(and GOAL...)` primitive."
  (%prove-all db
              (mapcar (lambda (goal)
                        (%subst-bindings bindings goal))
                      args)
              bindings
              state
              succeed
              fail))

(define-primitive %primitive-or (db args bindings state succeed fail)
  "Relational disjunction `(or GOAL...)`: succeed with each solution of any goal."
  (if (null args)
      (funcall fail)
      (%prove db
              (%subst-bindings bindings (first args))
              bindings
              state
              succeed
              (lambda ()
                (%primitive-or db (rest args) bindings state succeed fail)))))

(define-primitive %primitive-unify (db args bindings state succeed fail)
  "The relational `(= LEFT RIGHT)` goal."
  (declare (ignore db state))
  (%assert-primitive-arity '= args 2)
  (let ((next-bindings (%unify (first args) (second args) bindings)))
    (if (eq next-bindings +fail+)
        (funcall fail)
        (funcall succeed next-bindings fail))))

(define-primitive %primitive-true (db args bindings state succeed fail)
  "The `(true)` goal: succeed exactly once without touching the bindings."
  (declare (ignore db args state))
  (%assert-primitive-arity 'true args 0)
  (funcall succeed bindings fail))

(define-primitive %primitive-fail (db args bindings state succeed fail)
  "The `(fail)` goal: never succeed."
  (declare (ignore db args bindings state succeed))
  (%assert-primitive-arity 'fail args 0)
  (funcall fail))

(define-primitive %primitive-call (db args bindings state succeed fail)
  "The meta-call `(call GOAL)`: prove the (possibly variable) goal term GOAL."
  (%assert-primitive-arity 'call args 1)
  (%prove db (%subst-bindings bindings (first args)) bindings state succeed fail))

(define-primitive %primitive-findall (db args bindings state succeed fail)
  "Collect `(findall TEMPLATE GOAL RESULT)`: unify RESULT with the list of
TEMPLATE instances produced by every proof of GOAL. Succeeds once (with the
empty list when GOAL has no proof), which makes it a clean aggregation escape
hatch out of pure relational search."
  (%assert-primitive-arity 'findall args 3)
  (destructuring-bind (template goal result) args
    (let* ((solution-bindings (%collect-proof-bindings
                               db
                               (%subst-bindings bindings goal)
                               bindings
                               state))
           (items (mapcar (lambda (solution)
                            ;; Bind the template's goal-shared variables, then
                            ;; freshen any variables the goal left unbound so
                            ;; each collected item is independent, per ISO
                            ;; findall/3.
                            (%rename-variables (%subst-bindings solution template)))
                          solution-bindings))
           (next-bindings (%unify result items bindings)))
      (if (eq next-bindings +fail+)
          (funcall fail)
          (funcall succeed next-bindings fail)))))

(defun install-standard-primitives (db)
  "Install the reusable relational primitives into DB.
Provides `and/*`, `or/*`, `not/1`, `=/2`, plus the advanced predicates
`true/0`, `fail/0`, `call/1`, and `findall/3`."
  (add-primitive db 'and #'%primitive-and)
  (add-primitive db 'or #'%primitive-or)
  (add-primitive db 'not #'%primitive-not)
  (add-primitive db '= #'%primitive-unify)
  (add-primitive db 'true #'%primitive-true)
  (add-primitive db 'fail #'%primitive-fail)
  (add-primitive db 'call #'%primitive-call)
  (add-primitive db 'findall #'%primitive-findall)
  db)
