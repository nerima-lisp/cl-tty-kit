(in-package #:cl-tty-kit/prolog)

;;; --------------------------------------------------------------------------
;;; Search policy
;;; --------------------------------------------------------------------------

(defstruct (search-state (:constructor make-search-state))
  "Proof metadata: branch-local active goals plus query-local failed goal memo."
  (active-goals '() :type list)
  (failed-goals (make-hash-table :test 'equal) :type hash-table))

(defun %variables-in (term)
  (let ((variables '())
        (stack (list term)))
    (loop while stack do
      (let ((node (pop stack)))
        (cond
          ((variable-p node)
           (pushnew node variables))
          ((consp node)
           (push (rest node) stack)
           (push (first node) stack)))))
    variables))

(defun %rename-variables (term)
  (sublis (mapcar (lambda (variable)
                    (cons variable (gensym (symbol-name variable))))
                  (%variables-in term))
          term))

(defun %ground-term-p (term)
  (cond ((variable-p term) nil)
        ((consp term)
         (and (%ground-term-p (first term))
              (%ground-term-p (rest term))))
        (t t)))

(defun %active-goal-p (state goal-key)
  (member goal-key (search-state-active-goals state) :test #'equal))

(defun %failed-goal-p (state goal-key)
  (gethash goal-key (search-state-failed-goals state)))

(defun %push-active-goal (state goal-key)
  (make-search-state
   :active-goals (cons goal-key (search-state-active-goals state))
   :failed-goals (search-state-failed-goals state)))

(defun %memoize-failed-goal (state goal-key)
  (setf (gethash goal-key (search-state-failed-goals state)) t)
  nil)

(defun %collect-cps-bindings (runner)
  "Collect every binding produced by RUNNER's CPS succeed/fail protocol."
  (let ((results '()))
    (labels ((succeed (bindings resume)
               (push bindings results)
               (funcall resume))
             (fail ()
               (nreverse results)))
      (funcall runner #'succeed #'fail))))

(defun %prove-all (db goals bindings state succeed fail)
  (cond ((eq bindings +fail+)
         (funcall fail))
        ((null goals)
         (funcall succeed bindings fail))
        (t
         (%prove db
                 (first goals)
                 bindings
                 state
                 (lambda (next-bindings resume)
                   (%prove-all db
                               (rest goals)
                               next-bindings
                               state
                               succeed
                               resume))
                 fail))))

(defun %collect-proof-bindings (db goal &optional (bindings +no-bindings+)
                                    (state (make-search-state)))
  "Collect every successful binding set produced by proving GOAL in DB."
  (%collect-cps-bindings
   (lambda (succeed fail)
     (%prove-all db
                 (list goal)
                 bindings
                 state
                 succeed
                 fail))))

(defun %relation-slot (db relation accessor)
  (let ((entry (%relation-entry db relation)))
    (and entry (funcall accessor entry))))

(defun %relation-primitive (db relation)
  (%relation-slot db relation #'relation-entry-primitive))

(defun %relation-clauses (db relation)
  (%relation-slot db relation #'relation-entry-clauses))

(defun %prove-clause (db goal bindings state clause succeed fail)
  (let* ((clause (%rename-variables clause))
         (next-bindings (unify goal (clause-head clause) bindings)))
    (if (eq next-bindings +fail+)
        (funcall fail)
        (%prove-all db
                    (clause-body clause)
                    next-bindings
                    state
                    succeed
                    fail))))

(defun %prove-clauses (db goal bindings state clauses succeed fail)
  (if (null clauses)
      (funcall fail)
      (%prove-clause db
                     goal
                     bindings
                     state
                     (first clauses)
                     succeed
                     (lambda ()
                       (%prove-clauses db goal bindings state (rest clauses)
                                       succeed
                                       fail)))))

(defun %prove (db goal bindings state succeed fail)
  ;; A non-compound goal term -- an unbound variable, number, or bare atom that
  ;; can reach here through call/1, findall/3, or a variable goal in and/or -- is
  ;; not provable. Fail gracefully instead of crashing in GOAL-RELATION.
  (when (not (consp goal))
    (return-from %prove (funcall fail)))
  (let* ((resolved-goal (subst-bindings bindings goal))
         (goal-key (%normalized-term resolved-goal))
         (primitive (%relation-primitive db (goal-relation goal))))
    (cond (primitive
           (funcall primitive
                    db
                    (goal-arguments goal)
                    bindings
                    state
                    succeed
                    fail))
          ((%active-goal-p state goal-key)
           (funcall fail))
          ((and (%ground-term-p resolved-goal)
                (%failed-goal-p state goal-key))
           (funcall fail))
          (t
           (let* ((next-state (%push-active-goal state goal-key))
                 (foundp nil)
                 (clauses (%relation-clauses db (goal-relation goal))))
             (%prove-clauses db
                             goal
                             bindings
                             next-state
                             clauses
                             (lambda (next-bindings resume)
                               (setf foundp t)
                               (funcall succeed next-bindings resume))
                             (lambda ()
                               (when (and (%ground-term-p resolved-goal)
                                          (not foundp))
                                 (%memoize-failed-goal state goal-key))
                               (funcall fail))))))))

(defun solutions (db goal &optional (template goal))
  "Return TEMPLATE substituted with the bindings of every proof of GOAL."
  (mapcar (lambda (bindings)
            (subst-bindings bindings template))
          (%collect-proof-bindings db goal)))

(defun provable-p (db goal)
  "Return true when GOAL has at least one proof in DB."
  (not (null (%collect-proof-bindings db goal))))
