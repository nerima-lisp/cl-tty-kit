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
     :summary "render an initial dashboard frame followed by incremental updates")
    (:path "examples/boxed-panel.lisp"
     :summary "frame a rounded box with a title, padded fields, and colored status text")
    (:path "examples/mouse-decoding.lisp"
     :summary "decode SGR mouse press, release, wheel, and drag reports")
    (:path "examples/progress-dashboard.lisp"
     :summary "compose a boxed dashboard with colored progress bars and aligned columns")
    (:path "examples/layout-panels.lisp"
     :summary "split a frame into bordered panels with a sparkline and a columns table")
    (:path "examples/renderer-loop.lisp"
     :summary "drive a double-buffered renderer, emitting a full paint then a diff-only update")
    (:path "examples/interactive-dashboard.lisp"
     :summary "run a resize-aware resident TUI with fd readiness and incremental input decoding")
    (:path "examples/color-report.lisp"
     :summary "render a color gradient bar and a table of named color indices and luminance")
    (:path "examples/layout-dashboard.lisp"
     :summary "lay out a header, sidebar, main, and footer dashboard with layout-split constraints")
    (:path "examples/text-panel.lisp"
     :summary "frame a word-wrapped paragraph under an ellipsized title by display width")
    (:path "examples/hsl-rainbow.lisp"
     :summary "sweep the HSL hue circle across a panel with hsl-to-rgb color conversion")
    (:path "examples/styled-parse.lisp"
     :summary "recover text and style segments from an ANSI-styled string with parse-styled-string")
    (:path "examples/graphemes.lisp"
     :summary "split a mixed string into grapheme clusters and report each cluster's display width")
    (:path "examples/sixel-image.lisp"
     :summary "encode a small red-to-blue gradient image as a sixel DCS string")))

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
