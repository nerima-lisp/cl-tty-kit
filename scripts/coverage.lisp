(require :asdf)
(require :sb-cover)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (proclaim '(optimize sb-cover:store-coverage-data))
  (load (merge-pathnames #P"bootstrap.lisp"
                         (uiop:pathname-directory-pathname *load-truename*)))
  (cl-tty-kit/bootstrap:load-support-files))

(defparameter *coverage-timeout-seconds* 120)

(defmacro with-coverage-timeout ((label) &body body)
  `(handler-case
       (sb-ext:with-timeout *coverage-timeout-seconds*
         ,@body)
     (sb-ext:timeout ()
       (error "~A timed out after ~D seconds"
              ,label
              *coverage-timeout-seconds*))))

(defun coverage-entry-count ()
  (hash-table-count (car sb-int:*code-coverage-info*)))

(defun canonical-directory (path)
  (uiop:ensure-directory-pathname (truename path)))

(defun source-file-covered-p (path project-prefix)
  (and (search project-prefix path)
       (search "/src/" path)
       (probe-file path)))

(defun run-examples ()
  (dolist (file (cl-user::example-script-files))
    (format t "~&[RUN] ~A~%" file)
    (finish-output)
    (cl-tty-kit/bootstrap:run-example-file file)))

(let* ((scripts-dir (uiop:pathname-directory-pathname *load-truename*))
       (project-root (canonical-directory (merge-pathnames #P"../" scripts-dir)))
       (coverage-dir (merge-pathnames #P"coverage/" project-root))
       (project-prefix (namestring project-root)))
  (ensure-directories-exist coverage-dir)
  (sb-cover:clear-coverage)
  (format t "~&[COVERAGE] instrumented load~%")
  (finish-output)
  (with-coverage-timeout ("instrumented load")
    (cl-tty-kit/bootstrap:load-core-system))
  (format t "~&[COVERAGE] entries after load: ~D~%" (coverage-entry-count))
  (format t "~&[COVERAGE] tests~%")
  (finish-output)
  (with-coverage-timeout ("coverage tests")
    (cl-tty-kit/bootstrap:load-test-system)
    (cl-tty-kit/test:run-tests))
  (format t "~&[COVERAGE] entries after tests: ~D~%" (coverage-entry-count))
  (format t "~&[COVERAGE] examples~%")
  (finish-output)
  (with-coverage-timeout ("coverage examples")
    (run-examples))
  (format t "~&[COVERAGE] entries after examples: ~D~%" (coverage-entry-count))
  (format t "~&[COVERAGE] report -> ~A~%" coverage-dir)
  (finish-output)
  (sb-cover:report coverage-dir
                   :if-matches (lambda (path)
                                 (source-file-covered-p path project-prefix))))
