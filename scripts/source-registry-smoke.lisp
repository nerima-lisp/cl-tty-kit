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

(let* ((root (uiop:ensure-directory-pathname (uiop:getcwd)))
       (system-file (merge-pathnames #P"cl-tty-kit.asd" root))
       (preserved-entry (merge-pathnames #P"preserved/" root)))
  (unless (probe-file system-file)
    (error "Run this script from the project root so cl-tty-kit.asd is visible."))
  (let* ((sibling-root (uiop:pathname-directory-pathname root))
         (candidate-roots
           (remove-if-not #'probe-file
                          (list root
                                (merge-pathnames #P"../cl-codec-kit/" sibling-root)
                                (merge-pathnames #P"../cl-concurrent-kit/" sibling-root)
                                (merge-pathnames #P"../cl-boundary-kit/" sibling-root)
                                (merge-pathnames #P"../cl-date-kit/" sibling-root)
                                (merge-pathnames #P"../cl-host-kit/" sibling-root)
                                (merge-pathnames #P"../cl-weave/" sibling-root)
                                (merge-pathnames #P"../cl-prolog-kit/" sibling-root)
                                (merge-pathnames #P"../cl-parser-kit/" sibling-root)))))
    (asdf/source-registry:initialize-source-registry
     `(:source-registry
       ,@(mapcar (lambda (path) `(:tree ,(namestring path))) candidate-roots)
       :ignore-inherited-configuration)))
  (unless (asdf:find-system :cl-tty-kit)
    (error "Fresh source registry did not discover cl-tty-kit."))
  (unless (asdf:find-system :cl-tty-kit/test)
    (error "Fresh source registry did not discover cl-tty-kit/test."))
  (pushnew preserved-entry asdf:*central-registry* :test #'equal)
  (format t "~&[LOAD] cl-tty-kit via project bootstrap~%")
  (load (merge-pathnames #P"scripts/bootstrap.lisp" root))
  (unless (member preserved-entry asdf:*central-registry* :test #'equal)
    (error "Project bootstrap replaced the caller's ASDF central registry."))
  (handler-case
      (sb-ext:with-timeout 120
        (call-exported-function "CL-TTY-KIT/BOOTSTRAP" "LOAD-TEST-SYSTEM")
        (format t "~&[TEST] cl-tty-kit via project bootstrap~%")
        (call-exported-function "CL-TTY-KIT/TEST" "RUN-TESTS"))
    (sb-ext:timeout ()
      (error "source-registry smoke test timed out after 120 seconds"))))
