(require :asdf)

(require :sb-cover)

;; LOAD and the CL-TTY-KIT/BOOTSTRAP reference below must be separate
;; top-level forms: a single EVAL-WHEN form is read in full -- including the
;; CL-TTY-KIT/BOOTSTRAP:LOAD-SUPPORT-FILES symbol -- before any of it runs, so
;; the reader would hit that package before LOAD had a chance to define it.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (proclaim '(optimize sb-cover:store-coverage-data)))

(load
  (merge-pathnames
    #P"bootstrap.lisp"
    (uiop:pathname-directory-pathname *load-truename*)))

(cl-tty-kit/bootstrap:load-support-files)

;; CL-TTY-KIT/TEST is loaded at runtime by LOAD-TEST-SYSTEM below, inside the
;; same top-level LET* that goes on to call RUN-TESTS -- but the reader reads
;; that whole LET* before any of it runs, so a direct
;; CL-TTY-KIT/TEST:RUN-TESTS reference would hit a nonexistent package at read
;; time. Look the symbol up by name instead, deferring resolution to runtime.
(defparameter *coverage-timeout-seconds* 120)

(defmacro with-coverage-timeout ((label) &body body)
  `(cl-tty-kit/bootstrap:with-script-timeout (,label *coverage-timeout-seconds*) ,@body))

(defun coverage-entry-count ()
  "Return the number of SB-COVER instrumentation entries recorded so far."
  (let ((variable (find-symbol "*CODE-COVERAGE-INFO*" "SB-INT")))
    (if (and variable (boundp variable)) (hash-table-count (car (symbol-value variable)))
      0)))

(defun report-empty-p (coverage-dir)
  (let ((index-path (merge-pathnames #P"cover-index.html" coverage-dir)))
    (or
      (not (probe-file index-path))
      (with-open-file (stream index-path :direction :input)
        (loop for line = (read-line stream nil nil)
              while line
              thereis (search "No code coverage data found." line))))))

(defun canonical-directory (path)
  (uiop:ensure-directory-pathname (truename path)))



(progn
  (defun source-file-covered-p (path project-prefix)
    "Return true only for implementation files in this project.
Excludes cl-codec-kit explicitly (in addition to the PROJECT-PREFIX check) --
it is a real :DEPENDS-ON as of the UTF-8 delegation in src/utf8.lisp, and its
own encodings this project's tests never call (UTF-16/32, UCS-2, ASCII,
ISO-8859-1) should not count against this project's own coverage floor."
    (and (search project-prefix path) (search "/src/" path) (probe-file path)
         (not (search "cl-codec-kit" path))))

  (defun coverage-row-numbers (row)
  (loop with position = 0
        for cell-start = (search "<td" row :start2 position)
        while cell-start
        for content-start = (position (code-char 62) row :start cell-start)
        for cell-end = (and content-start
                            (search "</td>" row :start2 content-start))
        do (unless cell-end
             (error "Malformed SB-COVER report row."))
        collect (parse-integer row
                               :start (1+ content-start)
                               :end cell-end
                               :junk-allowed t) into values
        do (setf position (+ cell-end 5))
        finally (return (remove nil values))))

  (defun coverage-report-totals (coverage-dir)
    (let ((expression-covered 0)
          (expression-total 0)
          (branch-covered 0)
          (branch-total 0)
          (rows 0)
          (index-path (merge-pathnames #P"cover-index.html" coverage-dir)))
      (with-open-file (stream index-path :direction :input)
        (let ((report (make-string (file-length stream))))
          (read-sequence report stream)
          (loop with position = 0
                for row-start = (search "<tr class='" report :start2 position)
                while row-start
                for row-end = (search "</tr>" report :start2 row-start)
                do (unless row-end
                     (error "Malformed SB-COVER report at ~A." index-path))
                   (let ((row (subseq report row-start (+ row-end 5))))
                     (when (or (search "<tr class='odd'>" row)
                               (search "<tr class='even'>" row))
                       (let ((numbers (coverage-row-numbers row)))
                         (unless (member (length numbers) (quote (5 6)))
                           (error "Malformed SB-COVER source row in ~A." index-path))
                         (incf rows)
                         (incf expression-covered (first numbers))
                         (incf expression-total (second numbers))
                         (incf branch-covered (fourth numbers))
                         (incf branch-total (fifth numbers)))))
                   (setf position (+ row-end 5)))))
      (values expression-covered expression-total branch-covered branch-total rows)))

  (defun enforce-coverage-threshold (coverage-dir)
    (multiple-value-bind (expression-covered expression-total branch-covered branch-total rows)
        (coverage-report-totals coverage-dir)
      (when (or (zerop rows) (zerop expression-total) (zerop branch-total))
        (error "Coverage report at ~A has no source coverage data." coverage-dir))
      (format t "~&[COVERAGE] expression: ~D/~D; branch: ~D/~D~%"
              expression-covered expression-total branch-covered branch-total)
      (unless (and (>= (* expression-covered 100) (* expression-total 90))
                   (>= (* branch-covered 100) (* branch-total 90)))
        (error "Coverage threshold (90%%) not met: expression ~D/~D; branch ~D/~D."
               expression-covered expression-total branch-covered branch-total))))

  (defun run-examples ()
    (dolist (file (cl-user::example-script-files))
      (format t "~&[RUN] ~A~%" file)
      (finish-output)
      (cl-tty-kit/bootstrap:run-example-file file))))

(progn
  (let* ((scripts-dir (uiop:pathname-directory-pathname *load-truename*))
         (project-root (canonical-directory (merge-pathnames #P"../" scripts-dir)))
         (coverage-dir (merge-pathnames #P"coverage/" project-root))
         (project-prefix (namestring project-root)))
    (when (probe-file coverage-dir)
      (uiop:delete-directory-tree coverage-dir :validate t))
    (ensure-directories-exist coverage-dir)
    (sb-cover:clear-coverage)
    (format t "~&[COVERAGE] instrumented load~%")
    (finish-output)
    (with-coverage-timeout
      ("instrumented load")
      (cl-tty-kit/bootstrap:load-core-system :force t))
    (format t "~&[COVERAGE] entries after load: ~D~%" (coverage-entry-count))
    (format t "~&[COVERAGE] tests~%")
    (finish-output)
    (with-coverage-timeout
      ("coverage tests")
      (cl-tty-kit/bootstrap:load-test-system :force t)
      (cl-tty-kit/bootstrap:call-exported-function "CL-TTY-KIT/TEST" "RUN-TESTS"))
    (format t "~&[COVERAGE] entries after tests: ~D~%" (coverage-entry-count))
    (format t "~&[COVERAGE] examples~%")
    (finish-output)
    (with-coverage-timeout ("coverage examples") (run-examples))
    (format t "~&[COVERAGE] entries after examples: ~D~%" (coverage-entry-count))
    (format t "~&[COVERAGE] report -> ~A~%" coverage-dir)
    (finish-output)
    (with-coverage-timeout
      ("coverage report")
      (sb-cover:report
        coverage-dir
        :if-matches
        (lambda (path)
          (source-file-covered-p path project-prefix)))
      (progn
  (when (report-empty-p coverage-dir)
    (error
      "Coverage report at ~A did not capture any source coverage data."
      coverage-dir))
  (enforce-coverage-threshold coverage-dir))))
  (uiop:quit 0))
