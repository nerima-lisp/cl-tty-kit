(in-package #:cl-tty-kit/test)

(defun test-prolog-db-invariants ()
  (let ((db (tty-prolog:make-clause-db)))
    (is (eq db
            (tty-prolog:define-clauses db
              ((parent abraham isaac))))
        "define-clauses returns the database for chaining"))
  (labels ((exercise-db-error (kind)
             (ecase kind
               (primitive-clause
                (let ((db (tty-prolog:install-standard-primitives
                           (tty-prolog:make-clause-db))))
                  (tty-prolog:add-clause db '((and foo)))))
               (clause-primitive
                (let ((db (tty-prolog:make-clause-db)))
                  (tty-prolog:define-clauses db
                    ((parent abraham isaac)))
                  (tty-prolog:add-primitive db 'parent #'identity)))
               (invalid-db
                (tty-prolog:add-clause :not-a-db '((parent abraham isaac))))
               (empty-clause
                (tty-prolog:add-clause (tty-prolog:make-clause-db) '()))
               (dotted-clause
                (tty-prolog:add-clause (tty-prolog:make-clause-db)
                                       '((parent abraham isaac) . bad)))
               (variable-relation
                (tty-prolog:add-clause (tty-prolog:make-clause-db)
                                       '((?relation abraham isaac))))
               (invalid-primitive-relation
                (tty-prolog:add-primitive (tty-prolog:make-clause-db)
                                          '?relation
                                          #'identity))
               (invalid-primitive-function
                (tty-prolog:add-primitive (tty-prolog:make-clause-db)
                                          'parent
                                          :not-a-function)))))
    (do-test-case-bind (case +prolog-db-error-cases+ (kind message description))
      (signals (error condition)
          (exercise-db-error kind)
        (is (search message (princ-to-string condition))
            description)))))
