(in-package #:cl-tty-kit/test)

(defun test-prolog-primitives ()
  (do-test-case-bind (case +prolog-primitive-cases+
                           (predicate goal expected description))
    (is-equal expected
              (funcall predicate (%genealogy-db) goal)
              description))
  ;; Unlike the retired engine's hand-written primitives (which reported "expects
  ;; N arguments" for a wrong arity), cl-prolog's builtins are registered per
  ;; exact predicate indicator: a name called at an arity it does not support
  ;; denotes a different, undefined procedure and signals the catchable ISO
  ;; PROLOG-EXISTENCE-ERROR, same as calling any other undefined relation.
  (let ((db (%genealogy-db)))
    (signals (cl-prolog:prolog-existence-error condition)
        (cl-prolog:query-prolog db (list 'cl-prolog:findall '?x '(parent ?x ?y)))
      (is condition))
    (signals (cl-prolog:prolog-existence-error condition)
        (cl-prolog:query-prolog db '(= ?x))
      (is condition))
    (signals (cl-prolog:prolog-existence-error condition)
        (cl-prolog:query-prolog db (list 'cl-prolog:true 'extra))
      (is condition)))
  ;; CALL/N is ISO meta-call: extra arguments are appended to the inner goal
  ;; rather than making CALL itself arity-mismatched, so (call G extra) proves
  ;; G with one more argument -- here PARENT/3, which the rulebase never
  ;; defines, so it still signals PROLOG-EXISTENCE-ERROR, just against PARENT.
  (signals (cl-prolog:prolog-existence-error condition)
      (cl-prolog:query-prolog (%genealogy-db)
                              (list 'cl-prolog:call '(parent abraham isaac) 'extra))
    (is condition)))
