(require :asdf)

(defun call-exported-function (package-name symbol-name)
  (let* ((package (or (find-package package-name)
                      (error "Package ~A is not available." package-name)))
         (symbol (multiple-value-bind (symbol status)
                     (find-symbol symbol-name package)
                   (unless (eq status :external)
                     (error "Symbol ~A is not exported from ~A." symbol-name package-name))
                   symbol)))
    (funcall (symbol-function symbol))))

(let* ((root
         (uiop:ensure-directory-pathname
           (truename
             (merge-pathnames #P"../"
                              (uiop:pathname-directory-pathname *load-truename*)))))
       (system-file (merge-pathnames #P"cl-tty-kit.asd" root))
       (preserved-entry (merge-pathnames #P"preserved/" root)))
  (unless (probe-file system-file)
    (error "Project system file is not visible beside the smoke-test script."))
  (asdf/source-registry:initialize-source-registry
    `(:source-registry
       (:tree ,(namestring root))
       :ignore-inherited-configuration))
  (pushnew preserved-entry asdf:*central-registry* :test #'equal)
  (format t "~&[LOAD] cl-tty-kit via project bootstrap~%")
  (load (merge-pathnames #P"scripts/bootstrap.lisp" root))
  (unless (member preserved-entry asdf:*central-registry* :test #'equal)
    (error "Project bootstrap replaced the caller's ASDF central registry."))
  (handler-case
      (sb-ext:with-timeout 120
        (call-exported-function "CL-TTY-KIT/BOOTSTRAP" "LOAD-TEST-SYSTEM")
        (let ((loaded-system-file
                (asdf:system-source-file (asdf:find-system :cl-tty-kit))))
          (unless (equal (truename system-file) (truename loaded-system-file))
            (error "Bootstrap loaded cl-tty-kit from ~A instead of ~A."
                   loaded-system-file
                   system-file)))
        (format t "~&[TEST] cl-tty-kit via project bootstrap~%")
        (call-exported-function "CL-TTY-KIT/TEST" "RUN-TESTS"))
    (sb-ext:timeout ()
      (error "source-registry smoke test timed out after 120 seconds"))))
