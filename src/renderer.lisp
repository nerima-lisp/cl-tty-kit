(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; Double-buffered repaint helper
;;;
;;; A RENDERER holds a back buffer to draw into and a private snapshot of the
;;; previous frame. RENDERER-RENDER diffs the two, emits only the changes, then
;;; takes a fresh snapshot -- the standard TUI repaint loop, wrapped so callers
;;; never thread the previous screen/cursor by hand. The first render has no
;;; snapshot yet, so it repaints in full (RENDER-DIFF treats a NIL previous as a
;;; full redraw).
;;; --------------------------------------------------------------------------

(defstruct (renderer (:constructor %make-renderer (&key screen front cursor))
                     (:copier nil))
  "A double-buffered repaint helper. Draw into its back SCREEN each frame, then
call RENDERER-RENDER to emit only what changed since the previous frame."
  (screen nil :type screen)
  (front nil :type (or null screen))
  (cursor nil :type (or null cursor)))

(setf (documentation 'renderer-screen 'function)
      "Return the back-buffer SCREEN of RENDERER, the grid to draw the next
frame into.")

(defun make-renderer (width height &key initial-cell)
  "Create a RENDERER whose back buffer is a fresh WIDTH by HEIGHT SCREEN.
Each cell starts as an independent copy of INITIAL-CELL (a CELL template, a
character, or NIL for blank). The first RENDERER-RENDER repaints in full."
  (%make-renderer :screen (make-screen width height :initial-cell initial-cell)
                  :front nil
                  :cursor nil))

(defun %assert-renderer (renderer)
  (unless (renderer-p renderer)
    (error "RENDERER ~S must be a renderer." renderer))
  renderer)

(defun %assert-render-cursor (cursor)
  (unless (cursor-p cursor)
    (error "CURSOR ~S must be a cursor." cursor))
  cursor)

(defun renderer-width (renderer)
  "Return the column width of RENDERER's back buffer."
  (%assert-renderer renderer)
  (screen-width (renderer-screen renderer)))

(defun renderer-height (renderer)
  "Return the row height of RENDERER's back buffer."
  (%assert-renderer renderer)
  (screen-height (renderer-screen renderer)))

(defun %snapshot-cursor (cursor)
  (make-cursor :x (cursor-x cursor)
               :y (cursor-y cursor)
               :visible (cursor-visible-p cursor)))

(defun renderer-render (renderer &key stream cursor)
  "Emit the changes needed to bring the terminal to RENDERER's back buffer.
Diffs the back buffer against the previous frame and returns the ANSI string
(or writes it to STREAM and returns STREAM). When CURSOR is supplied the frame
also finishes in that cursor state, diffed against the previous frame's cursor.
After emitting, RENDERER snapshots the current screen and cursor as the new
previous frame, so the next call diffs against this one."
  (%assert-renderer renderer)
  (when cursor
    (%assert-render-cursor cursor))
  (let* ((back (renderer-screen renderer))
         (front (renderer-front renderer))
         (output (if cursor
                     (render-frame-diff back front cursor
                                        :previous-cursor (renderer-cursor renderer)
                                        :stream stream)
                     (render-diff back front stream))))
    (setf (renderer-front renderer) (screen-copy back))
    (when cursor
      (setf (renderer-cursor renderer) (%snapshot-cursor cursor)))
    output))

(defun renderer-clear (renderer &key cell)
  "Reset RENDERER's back buffer to CELL (a template, character, or NIL for
blank), returning RENDERER. The change is emitted by the next RENDERER-RENDER."
  (%assert-renderer renderer)
  (screen-clear (renderer-screen renderer) :cell cell)
  renderer)

(defun renderer-resize (renderer width height &key initial-cell)
  "Resize RENDERER's back buffer to WIDTH by HEIGHT, returning RENDERER.
The previous-frame snapshot is dropped so the next RENDERER-RENDER repaints in
full, since a resized terminal cannot be updated by a diff."
  (%assert-renderer renderer)
  (screen-resize (renderer-screen renderer) width height
                 :initial-cell initial-cell)
  (setf (renderer-front renderer) nil
        (renderer-cursor renderer) nil)
  renderer)
