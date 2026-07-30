(in-package #:cl-tty-kit/test)

(describe "prolog builtin predicates"
  (dolist (case +prolog-primitive-cases+)
    (destructuring-bind (predicate goal expected description) case
      (it description
        (expect (funcall predicate (%genealogy-db) goal) :to-equal expected))))
  ;; Unlike the retired engine's hand-written primitives (which reported "expects
  ;; N arguments" for a wrong arity), cl-prolog's builtins are registered per
  ;; exact predicate indicator: a name called at an arity it does not support
  ;; denotes a different, undefined procedure and signals the catchable ISO
  ;; PROLOG-EXISTENCE-ERROR, same as calling any other undefined relation.
  (it "a wrong-arity findall call signals prolog-existence-error"
    (let ((db (%genealogy-db)))
      (expect (lambda () (cl-prolog:query-prolog db (list 'cl-prolog:findall '?x '(parent ?x ?y))))
              :to-throw 'cl-prolog:prolog-existence-error)))
  (it "a wrong-arity = call signals prolog-existence-error"
    (expect (lambda () (cl-prolog:query-prolog (%genealogy-db) '(= ?x)))
            :to-throw 'cl-prolog:prolog-existence-error))
  (it "a wrong-arity true call signals prolog-existence-error"
    (expect (lambda () (cl-prolog:query-prolog (%genealogy-db) (list 'cl-prolog:true 'extra)))
            :to-throw 'cl-prolog:prolog-existence-error))
  ;; CALL/N is ISO meta-call: extra arguments are appended to the inner goal
  ;; rather than making CALL itself arity-mismatched, so (call G extra) proves
  ;; G with one more argument -- here PARENT/3, which the rulebase never
  ;; defines, so it still signals PROLOG-EXISTENCE-ERROR, just against PARENT.
  (it "call/n appends its extra argument to the inner goal"
    (expect (lambda ()
              (cl-prolog:query-prolog (%genealogy-db)
                                      (list 'cl-prolog:call '(parent abraham isaac) 'extra)))
            :to-throw 'cl-prolog:prolog-existence-error)))
