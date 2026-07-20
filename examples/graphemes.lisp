(require :asdf)

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(in-package #:cl-user)

(defvar *cl-tty-kit-run-example-on-load* t)

(defun graphemes-example ()
  "Split a mixed string into grapheme clusters and report each cluster's width.
Shows how a base plus combining mark is one cluster (and one column) while a CJK
ideograph is one code point but two columns."
  (let* ((text (concatenate 'string
                            "e" (string (code-char #x0301))          ; e + acute = é
                            " " (string (code-char #x4E00))          ; CJK 一
                            (string (code-char #x4E8C))              ; CJK 二
                            " ab"))
         (clusters (cl-tty-kit:string-graphemes text)))
    (with-output-to-string (out)
      (format out "~D clusters, ~D display columns:~%"
              (cl-tty-kit:grapheme-count text)
              (cl-tty-kit:string-width text))
      (dolist (cluster clusters)
        (format out "  cluster ~S : ~D code point(s), width ~D~%"
                cluster (length cluster) (cl-tty-kit:grapheme-width cluster))))))

(defun run-graphemes-example ()
  (format t "~A" (graphemes-example)))

(when *cl-tty-kit-run-example-on-load*
  (run-graphemes-example))
