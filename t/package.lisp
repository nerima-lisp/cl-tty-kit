(require :asdf)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package '#:cl-tty-kit/test)
    (defpackage #:cl-tty-kit/test
      (:use #:cl #:uiop #:cl-tty-kit)
      ;; cl-weave is the test framework every file in t/ is migrating onto (see
      ;; t/suite.lisp's RUN-TESTS): CL:DESCRIBE is shadowed in favor of
      ;; cl-weave's suite-registration macro, and EXPECT/IT/IT-PROPERTY are the
      ;; DSL migrated files register cases with.
      (:shadowing-import-from #:cl-weave #:describe)
      (:import-from #:cl-weave #:expect #:it #:it-property)
      (:export #:run-tests))))

(in-package #:cl-tty-kit/test)
