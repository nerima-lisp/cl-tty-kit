(in-package #:cl-tty-kit/prolog)

;;; --------------------------------------------------------------------------
;;; Clause data
;;; --------------------------------------------------------------------------

(declaim (ftype function variable-p))

(defstruct (clause-db (:constructor %make-clause-db) (:copier nil))
  "An explicit set of clauses and primitives keyed by relation symbol."
  (relations (make-hash-table :test 'eq) :type hash-table))

(defstruct (relation-entry (:constructor %make-relation-entry) (:copier nil))
  "A relation entry keeps clauses and an optional primitive implementation apart.
CLAUSES-TAIL points at the last clause cons so ADD-CLAUSE appends in O(1) while
preserving definition order."
  (clauses '() :type list)
  (clauses-tail nil :type list)
  (primitive nil))

(defun clause-head (clause) (first clause))
(defun clause-body (clause) (rest clause))
(defun goal-relation (goal) (first goal))
(defun goal-arguments (goal) (rest goal))

(defun %relation-entry (db relation)
  (gethash relation (clause-db-relations db)))

(defun %ensure-relation-entry (db relation)
  (or (%relation-entry db relation)
      (setf (gethash relation (clause-db-relations db))
            (%make-relation-entry))))

(defun add-clause (db clause)
  "Add CLAUSE, a list (HEAD . BODY), to DB and return its relation symbol."
  (let* ((stored-clause (copy-tree clause))
         (relation (goal-relation (clause-head stored-clause))))
    (unless (and (symbolp relation) (not (variable-p relation)))
      (error "Clause head must start with a relation symbol: ~S" clause))
    (let ((entry (%ensure-relation-entry db relation))
          (cell (list stored-clause)))
      (when (relation-entry-primitive entry)
        (error "Relation ~S is a primitive and cannot take clauses." relation))
      (if (relation-entry-clauses-tail entry)
          (setf (cdr (relation-entry-clauses-tail entry)) cell)
          (setf (relation-entry-clauses entry) cell))
      (setf (relation-entry-clauses-tail entry) cell))
    relation))

(defun add-primitive (db relation function)
  "Bind RELATION in DB to a primitive FUNCTION.

FUNCTION receives six arguments: DB, the goal ARGS, the current BINDINGS, the
branch-local search STATE, a success CONTINUATION, and a failure CONTINUATION."
  (let ((entry (%ensure-relation-entry db relation)))
    (when (relation-entry-clauses entry)
      (error "Relation ~S already has clauses and cannot become primitive." relation))
    (setf (relation-entry-primitive entry) function))
  relation)

(defmacro define-primitive (name (db args bindings state succeed fail) &body body)
  "Define a primitive relation with the canonical engine calling convention."
  `(defun ,name (,db ,args ,bindings ,state ,succeed ,fail)
     ,@body))

(defun make-clause-db ()
  "Create and return a fresh, empty clause database."
  (%make-clause-db))

(defmacro define-clauses (db &body clauses)
  "Add each CLAUSE to DB and return DB, evaluated once, for chaining.
Each CLAUSE is an unquoted (HEAD . BODY) list such as
  ((parent abraham isaac))
or
  ((ancestor ?a ?b) (parent ?a ?c) (ancestor ?c ?b))."
  (let ((database (gensym "DB")))
    `(let ((,database ,db))
       ,@(mapcar (lambda (clause) `(add-clause ,database ',clause)) clauses)
       ,database)))
