(in-package #:cl-tty-kit/prolog)

;;; --------------------------------------------------------------------------
;;; Bindings and term rewriting
;;; --------------------------------------------------------------------------

(declaim (ftype function unify))

(defparameter +fail+ nil
  "The binding value returned when unification fails.")

(defparameter +no-bindings+ '((t . t))
  "The binding value that represents success with no variable bindings.")

(defparameter +max-prolog-term-depth+ 4096
  "Maximum nesting accepted by public Prolog term APIs.")

(defun variable-p (term)
  "Return true when TERM is a logic variable (a symbol whose name starts `?`)."
  (and (symbolp term)
       (let ((name (symbol-name term)))
         (and (plusp (length name))
              (char= (char name 0) #\?)))))

(defun %assert-prolog-term-safe (term role)
  (let ((path (make-hash-table :test 'eq)))
    (labels ((visit (node depth)
               (when (> depth +max-prolog-term-depth+)
                 (error "Prolog ~A exceeds maximum nesting depth ~D."
                        role +max-prolog-term-depth+))
               (when (consp node)
                 (when (gethash node path)
                   (error "Prolog ~A contains a circular term." role))
                 (setf (gethash node path) t)
                 (visit (first node) (1+ depth))
                 (visit (rest node) (1+ depth))
                 (remhash node path))))
      (visit term 0)
      term)))

(defun %proper-binding-list-p (list)
  (loop for cursor = list then (rest cursor)
        while (consp cursor)
        finally (return (null cursor))))

(defun %assert-bindings-safe (bindings)
  (cond ((eq bindings +fail+) bindings)
        ((not (%proper-binding-list-p bindings))
         (error "Prolog bindings must be a proper association list."))
        (t
         (loop for binding in bindings do
           (unless (consp binding)
             (error "Prolog binding entry must be a cons cell, got ~S." binding))
           (unless (or (eq binding (first +no-bindings+))
                       (variable-p (car binding)))
             (error "Prolog binding variable must be a logic variable, got ~S."
                    (car binding)))
           (%assert-prolog-term-safe (car binding) "binding variable")
           (%assert-prolog-term-safe (cdr binding) "binding value"))
         bindings)))

(defun get-binding (variable bindings)
  (assoc variable bindings))

(defun binding-value (binding)
  (cdr binding))

(defun lookup-variable (variable bindings)
  (binding-value (get-binding variable bindings)))

(defun extend-bindings (variable value bindings)
  (cons (cons variable value)
        (if (eq bindings +no-bindings+) nil bindings)))

(defun %walk-binding (term bindings &optional (seen (make-hash-table :test 'eq)))
  (if (and (variable-p term) (get-binding term bindings))
      (progn
        (when (gethash term seen)
          (error "Prolog bindings contain a circular variable chain at ~S." term))
        (setf (gethash term seen) t)
        (%walk-binding (lookup-variable term bindings) bindings seen))
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
  (let ((next (%unify (first left) (first right) bindings)))
    (%unify (rest left) (rest right) next)))

(defun %unify (left right bindings)
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

(defun unify (left right &optional (bindings +no-bindings+))
  "Unify LEFT and RIGHT under BINDINGS, returning extended bindings or +FAIL+."
  (%assert-prolog-term-safe left "left term")
  (%assert-prolog-term-safe right "right term")
  (%assert-bindings-safe bindings)
  (%unify left right bindings))

(defun %subst-bindings (bindings term)
  (let ((resolved-term (%walk-binding term bindings)))
    (cond ((eq bindings +fail+) +fail+)
          ((eq bindings +no-bindings+) resolved-term)
          ((atom resolved-term) resolved-term)
          (t (cons (%subst-bindings bindings (first resolved-term))
                   (%subst-bindings bindings (rest resolved-term)))))))

(defun subst-bindings (bindings term)
  "Substitute every bound variable in TERM with its value under BINDINGS."
  (%assert-prolog-term-safe term "substitution term")
  (%assert-bindings-safe bindings)
  (%subst-bindings bindings term))

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
