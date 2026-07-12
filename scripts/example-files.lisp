(in-package #:cl-user)

(defparameter *example-scripts*
  '((:path "examples/simple-render.lisp"
     :summary "full repaint of a small screen")
    (:path "examples/styled-render.lisp"
     :summary "styled cells with modifier, foreground, and background ANSI output")
    (:path "examples/key-decoding.lisp"
     :summary "decode printable, modified, and paste-related input events")
    (:path "examples/streaming-paste.lisp"
     :summary "collect a bracketed paste block across streaming input chunks")
    (:path "examples/frame-render.lisp"
     :summary "compose a frame render with an explicit final cursor state")
    (:path "examples/screen-update.lisp"
     :summary "diff two screens and emit only the changed cells")
    (:path "examples/event-loop.lisp"
     :summary "compose a deterministic terminal event loop from streaming decode and diff rendering")
    (:path "examples/terminal-session.lisp"
     :summary "scope alternate-screen lifecycle, cursor visibility, and input modes")
    (:path "examples/status-dashboard.lisp"
     :summary "render an initial dashboard frame followed by incremental updates")))

(defun example-scripts ()
  *example-scripts*)

(defun example-script-files ()
  (mapcar (lambda (entry)
            (getf entry :path))
          (example-scripts)))

(defun example-summary (file)
  (getf (find file (example-scripts)
              :key (lambda (entry)
                     (getf entry :path))
              :test #'string=)
        :summary))

(defun %example-symbol-name (file prefix)
  (if (string= prefix "")
      (format nil "~A-EXAMPLE"
              (string-upcase (pathname-name file)))
      (format nil "~A-~A-EXAMPLE"
              prefix
              (string-upcase (pathname-name file)))))

(defun example-function-symbol (file)
  (find-symbol (%example-symbol-name file "")
               :cl-user))
