(in-package #:cl-tty-kit)

(defun render-screen (screen &optional stream)
  "Render SCREEN as a complete ANSI string or write it to STREAM."
  (%render-screen-output screen stream))

(defun render-cursor (cursor &optional stream)
  "Render CURSOR as ANSI cursor control output."
  (%render-cursor-output cursor stream))

(defun render-diff (screen previous &optional stream)
  "Render only the changes between SCREEN and PREVIOUS."
  (%render-diff-output screen previous stream))

(defun render-frame (screen cursor &optional stream)
  "Render SCREEN and CURSOR as a complete frame."
  (%render-frame-output screen cursor stream))

(defun render-frame-diff (screen previous cursor &key previous-cursor stream)
  "Render a diff frame from PREVIOUS to SCREEN and finish in CURSOR state."
  (%render-frame-diff-output screen previous cursor previous-cursor stream))
