(in-package #:cl-tty-kit/test)

(defun %genealogy-db ()
  (cl-prolog:prolog
    ((parent abraham isaac))
    ((parent isaac jacob))
    ((parent jacob joseph))
    ((ancestor ?a ?b) (parent ?a ?b))
    ((ancestor ?a ?b) (parent ?a ?c) (ancestor ?c ?b))))

(defun %many-solutions-db ()
  (cl-prolog:prolog
    ((value one))
    ((value two))
    ((value three))))

(defun %project-variable (database goal variable)
  "Return VARIABLE's binding from every solution of GOAL against DATABASE."
  (mapcar (lambda (solution) (cl-prolog:solution-binding variable solution))
          (cl-prolog:query-prolog database goal)))

(defun %check-query (db goal template expected description &key set-p)
  (let ((actual (%project-variable db goal template)))
    (if set-p
        (is-equal (%normalize-solutions expected)
                  (%normalize-solutions actual)
                  description)
        (is-equal expected
                  actual
                  description))))

(defun %normalize-solutions (solutions)
  (sort (copy-list solutions)
        #'string<
        :key #'prin1-to-string))

(defun %not-provable-p (database goal)
  (not (cl-prolog:prolog-succeeds-p database goal)))

(defun %solve-variable (database goal)
  (%project-variable database goal '?x))

(defun %solve-parent (database goal)
  (%project-variable database goal '?p))

(defun %solve-result (database goal)
  (%project-variable database goal '?result))
