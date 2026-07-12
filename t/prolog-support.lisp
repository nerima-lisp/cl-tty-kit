(in-package #:cl-tty-kit/test)

(defun %genealogy-db ()
  (let ((db (tty-prolog:install-standard-primitives (tty-prolog:make-clause-db))))
    (tty-prolog:define-clauses db
      ((parent abraham isaac))
      ((parent isaac jacob))
      ((parent jacob joseph))
      ((ancestor ?a ?b) (parent ?a ?b))
      ((ancestor ?a ?b) (parent ?a ?c) (ancestor ?c ?b)))
    db))

(defun %check-query (db goal template expected description &key set-p)
  (let ((actual (tty-prolog:solutions db goal template)))
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
  (not (tty-prolog:provable-p database goal)))

(defun %solve-variable (database goal)
  (tty-prolog:solutions database goal '?x))

(defun %solve-parent (database goal)
  (tty-prolog:solutions database goal '?p))
