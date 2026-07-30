(in-package #:cl-tty-kit/prolog-tests)

(describe "unify"
  (it "unifies a shared free variable across two terms"
    (flet ((unified (left right)
             (multiple-value-bind (env ok) (cl-prolog:unify left right)
               (and ok (cl-prolog:logic-substitute left env)))))
      (expect (unified '(?x b) '(a ?y)) :to-equal '(a b))
      (expect (unified '(?x ?x) '(a a)) :to-equal '(a a))))
  (it "rejects binding one variable to two distinct constants"
    (multiple-value-bind (env ok) (cl-prolog:unify '(?x ?x) '(a b))
      (declare (ignore env))
      (expect (not ok))))
  (it "the occurs check rejects an infinite term"
    (multiple-value-bind (env ok) (cl-prolog:unify '?x '(f ?x))
      (declare (ignore env))
      (expect (not ok))))
  (it "a circular host term fails unification instead of looping"
    ;; A directly circular host cons -- built by hand, never through the reader
    ;; or the engine's own construction -- unifies safely rather than looping or
    ;; erroring: cl-prolog compares cyclic structure coinductively.
    (let ((term (list 'loop)))
      (setf (rest term) term)
      (multiple-value-bind (env ok) (cl-prolog:unify term '(loop))
        (declare (ignore env))
        (expect (not ok))))))
