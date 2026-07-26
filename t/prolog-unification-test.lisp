(in-package #:cl-tty-kit/test)

(defun test-prolog-unification ()
  (flet ((unified (left right)
           (multiple-value-bind (env ok) (cl-prolog:unify left right)
             (and ok (cl-prolog:logic-substitute left env)))))
    (is-equal '(a b) (unified '(?x b) '(a ?y)))
    (is-equal '(a a) (unified '(?x ?x) '(a a))))
  (multiple-value-bind (env ok) (cl-prolog:unify '(?x ?x) '(a b))
    (declare (ignore env))
    (is (not ok) "distinct constants cannot bind one variable twice"))
  (multiple-value-bind (env ok) (cl-prolog:unify '?x '(f ?x))
    (declare (ignore env))
    (is (not ok) "the occurs check rejects an infinite term"))
  ;; A directly circular host cons -- built by hand, never through the reader
  ;; or the engine's own construction -- unifies safely rather than looping or
  ;; erroring: cl-prolog compares cyclic structure coinductively.
  (let ((term (list 'loop)))
    (setf (rest term) term)
    (multiple-value-bind (env ok) (cl-prolog:unify term '(loop))
      (declare (ignore env))
      (is (not ok) "a circular host term fails unification instead of looping"))))
