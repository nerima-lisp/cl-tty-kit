(in-package #:cl-tty-kit)

(defun %render-output (commands stream)
  (%render-commands-output commands stream))

(defmacro define-render-function (name lambda-list docstring command-form)
  `(defun ,name ,lambda-list
     ,docstring
     (%render-output ,command-form stream)))

(define-render-function render-screen
    (screen &optional stream)
  "Render SCREEN as a complete ANSI string or write it to STREAM."
  (%screen-render-commands screen))

(define-render-function render-cursor
    (cursor &optional stream)
  "Render CURSOR state as ANSI output or write it to STREAM."
  (%cursor-render-commands cursor))

(define-render-function render-diff
    (screen previous &optional stream)
  "Render only the changes between SCREEN and PREVIOUS."
  (%preferred-diff-commands screen previous))

(defun %frame-render-commands (screen cursor)
  (append (%screen-render-commands screen)
          (%cursor-render-commands cursor)))

(define-render-function render-frame
    (screen cursor &optional stream)
  "Render SCREEN as a full frame and finish in CURSOR state."
  (%frame-render-commands screen cursor))

(define-render-function render-frame-diff
    (screen previous cursor
            &key previous-cursor stream)
  "Render a diff frame from PREVIOUS to SCREEN and finish in CURSOR state."
  (%frame-diff-render-commands screen previous cursor previous-cursor))
