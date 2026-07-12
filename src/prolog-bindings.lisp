(in-package #:cl-tty-kit/prolog)

;;; --------------------------------------------------------------------------
;;; Bindings and term rewriting
;;; --------------------------------------------------------------------------

(declaim (ftype function unify))

(defparameter +fail+ nil
  "The binding value returned when unification fails.")

(defparameter +no-bindings+ '((t . t))
  "The binding value that represents success with no variable bindings.")

(defun variable-p (term)
  "Return true when TERM is a logic variable (a symbol whose name starts `?`)."
  (and (symbolp term)
       (let ((name (symbol-name term)))
         (and (plusp (length name))
              (char= (char name 0) #\?)))))

(defun get-binding (variable bindings)
  (assoc variable bindings))

(defun binding-value (binding)
  (cdr binding))

(defun lookup-variable (variable bindings)
  (binding-value (get-binding variable bindings)))

(defun extend-bindings (variable value bindings)
  (cons (cons variable value)
        (if (eq bindings +no-bindings+) nil bindings)))

(defun %walk-binding (term bindings)
  (if (and (variable-p term) (get-binding term bindings))
      (%walk-binding (lookup-variable term bindings) bindings)
      term))

(defun %occurs-in-p (variable term bindings)
  (let ((resolved-term (%walk-binding term bindings)))
    (cond ((eq variable resolved-term) t)
          ((consp resolved-term)
           (or (%occurs-in-p variable (first resolved-term) bindings)
               (%occurs-in-p variable (rest resolved-term) bindings)))
          (t nil))))

(defun %bind-variable (variable term bindings)
  (let ((resolved-term (%walk-binding term bindings)))
    (cond ((eq variable resolved-term) bindings)
          ((%occurs-in-p variable resolved-term bindings) +fail+)
          (t (extend-bindings variable resolved-term bindings)))))

(defun %unify-conses (left right bindings)
  (let ((next (unify (first left) (first right) bindings)))
    (unify (rest left) (rest right) next)))

(defun unify (left right &optional (bindings +no-bindings+))
  "Unify LEFT and RIGHT under BINDINGS, returning extended bindings or +FAIL+."
  (cond ((eq bindings +fail+) +fail+)
        (t
         (let ((resolved-left (%walk-binding left bindings))
               (resolved-right (%walk-binding right bindings)))
           (cond ((eql resolved-left resolved-right) bindings)
                 ((variable-p resolved-left)
                  (%bind-variable resolved-left resolved-right bindings))
                 ((variable-p resolved-right)
                  (%bind-variable resolved-right resolved-left bindings))
                 ((and (consp resolved-left) (consp resolved-right))
                  (%unify-conses resolved-left resolved-right bindings))
                 (t +fail+))))))

(defun subst-bindings (bindings term)
  "Substitute every bound variable in TERM with its value under BINDINGS."
  (let ((resolved-term (%walk-binding term bindings)))
    (cond ((eq bindings +fail+) +fail+)
          ((eq bindings +no-bindings+) resolved-term)
          ((atom resolved-term) resolved-term)
          (t (cons (subst-bindings bindings (first resolved-term))
                   (subst-bindings bindings (rest resolved-term)))))))

(defun %normalized-term (term)
  "Return TERM with all logic variables renamed to deterministic placeholders."
  (let ((variables (make-hash-table :test 'eq))
        (next-index 0))
    (labels ((normalize (node)
               (cond ((variable-p node)
                      (or (gethash node variables)
                          (setf (gethash node variables)
                                (list :var (prog1 next-index
                                             (incf next-index))))))
                     ((consp node)
                      (cons (normalize (first node))
                            (normalize (rest node))))
                     (t node))))
      (normalize term))))
