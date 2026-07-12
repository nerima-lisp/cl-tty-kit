(in-package #:cl-tty-kit/test)

(defun test-render ()
  (test-render-examples)
  (test-render-core)
  (test-render-diff)
  t)
