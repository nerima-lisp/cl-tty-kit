(in-package #:cl-tty-kit/prolog)

;;; --------------------------------------------------------------------------
;;; Primitive relations
;;; --------------------------------------------------------------------------

(define-primitive %primitive-not (db args bindings state succeed fail)
  "Negation as failure: succeed when the single goal argument has no proof."
  (if (null (%collect-proof-bindings
             db
             (subst-bindings bindings (first args))
             bindings
             state))
      (funcall succeed bindings fail)
      (funcall fail)))

(define-primitive %primitive-and (db args bindings state succeed fail)
  "The relational `(and GOAL...)` primitive."
  (%prove-all db
              (mapcar (lambda (goal)
                        (subst-bindings bindings goal))
                      args)
              bindings
              state
              succeed
              fail))

(define-primitive %primitive-unify (db args bindings state succeed fail)
  "The relational `(= LEFT RIGHT)` goal."
  (declare (ignore db state))
  (let ((next-bindings (unify (first args) (second args) bindings)))
    (if (eq next-bindings +fail+)
        (funcall fail)
        (funcall succeed next-bindings fail))))

(defun install-standard-primitives (db)
  "Install the reusable `and/*`, `not/1`, and `=/2` primitives into DB."
  (add-primitive db 'and #'%primitive-and)
  (add-primitive db 'not #'%primitive-not)
  (add-primitive db '= #'%primitive-unify)
  db)
