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
(defstruct (renderer
    (:constructor
      %make-renderer
      (&key screen front cursor diff-plan rendered-generation))
    (:copier nil)) "A double-buffered repaint helper. Draw into its back SCREEN each frame, then call RENDERER-RENDER to emit only what changed since the previous frame."
  (screen nil :type screen)
  (front nil :type (or null screen))
  (cursor nil :type (or null cursor))
  (diff-plan nil :type (or null diff-plan))
  (rendered-generation nil :type (or null fixnum)))

(document-function
  'renderer-screen
  "Return the back-buffer SCREEN of RENDERER, the grid to draw the next
frame into.")

(defun make-renderer (width height &key initial-cell)
  "Create a RENDERER whose back buffer is a fresh WIDTH by HEIGHT SCREEN. INITIAL-CELL (a CELL template, character, or NIL for blank) is shared safely until a screen mutation replaces an entry. The first RENDERER-RENDER repaints in full."
  (let ((screen (make-screen width height :initial-cell initial-cell)))
    (%make-renderer
      :screen
      screen
      :front
      nil
      :cursor
      nil
      :diff-plan
      (%make-screen-diff-plan screen))))

(define-validating-assert
  %assert-renderer
  (renderer)
  (renderer-p renderer)
  "RENDERER ~S must be a renderer."
  renderer)

(define-validating-assert
  %assert-render-cursor
  (cursor)
  (cursor-p cursor)
  "CURSOR ~S must be a cursor."
  cursor)

(defun renderer-width (renderer)
  "Return the column width of RENDERER's back buffer."
  (%assert-renderer renderer)
  (screen-width (renderer-screen renderer)))

(defun renderer-height (renderer)
  "Return the row height of RENDERER's back buffer."
  (%assert-renderer renderer)
  (screen-height (renderer-screen renderer)))

(defmacro %snapshot-cursor (cursor)
  `(let ((cursor ,cursor))
    (make-cursor
      :x
      (cursor-x cursor)
      :y
      (cursor-y cursor)
      :visible
      (cursor-visible-p cursor))))

(defmacro %snapshot-renderer-cursor (renderer cursor)
  "Store CURSOR in RENDERER without replacing an existing private snapshot."
  `(let ((renderer ,renderer)
         (cursor ,cursor))
     (let ((snapshot (renderer-cursor renderer)))
       (if snapshot
           (setf (cursor-x snapshot) (cursor-x cursor)
                 (cursor-y snapshot) (cursor-y cursor)
                 (cursor-visible-p snapshot) (cursor-visible-p cursor))
         (setf (renderer-cursor renderer) (%snapshot-cursor cursor))))))

(defmacro %snapshot-renderer-screen (renderer back &key full-repaint-p)
  "Update RENDERER's front screen after a successful render of BACK."
  `(let ((renderer ,renderer)
         (back ,back)
         (full-repaint-p ,full-repaint-p))
     (declare (type renderer renderer)
              (type screen back))
     (let ((front (renderer-front renderer))
           (plan (renderer-diff-plan renderer)))
       (declare (type (or null screen) front)
                (type (or null diff-plan) plan))
       (cond
         ((or (null front)
              (/= (screen-width front) (screen-width back))
              (/= (screen-height front) (screen-height back)))
          (setf (renderer-front renderer) (screen-copy back)))
         (full-repaint-p
          (replace (screen-cells front) (screen-cells back))
          front)
         ((zerop (fill-pointer (diff-plan-operations plan)))
          front)
         (t
          (%copy-diff-plan-cells front back plan))))))

(defun renderer-render (renderer &key stream cursor)
  "Emit the changes needed to bring the terminal to the RENDERER back buffer. Diffs the back buffer against the previous frame and returns the ANSI string (or writes it to STREAM and returns STREAM) as its primary value. Its secondary value is true exactly when it wrote terminal output. When CURSOR is supplied the frame also finishes in that cursor state, diffed against the previous frame cursor. After emitting, RENDERER snapshots the current screen and cursor as the new previous frame, so the next call diffs against this one. An uncursored render invalidates the saved cursor because rendering output may move the terminal cursor without restoring it."
  (%assert-renderer renderer)
  (when cursor
    (%assert-render-cursor cursor))
  (let* ((back (renderer-screen renderer))
         (front (renderer-front renderer))
         (plan (renderer-diff-plan renderer))
         (rendered-generation (renderer-rendered-generation renderer))
         (back-generation (screen-generation back)))
    (declare (type screen back)
             (type (or null screen) front)
             (type (or null diff-plan) plan)
             (type (or null fixnum) rendered-generation)
             (type fixnum back-generation))
    (if (and front
             (eql rendered-generation back-generation)
             (or (null cursor)
                 (and (renderer-cursor renderer)
                      (%cursor-equal-p cursor (renderer-cursor renderer)))))
        (progn
          (unless cursor
            (setf (renderer-cursor renderer) nil))
          (values (or stream "") nil))
        (multiple-value-bind (output diff-output-p full-repaint-p)
            (if cursor
                (%render-frame-diff-output
                  back
                  front
                  cursor
                  (renderer-cursor renderer)
                  stream
                  plan
                  rendered-generation)
                (%render-diff-output
                  back
                  front
                  stream
                  plan
                  rendered-generation))
          (%snapshot-renderer-screen renderer back :full-repaint-p full-repaint-p)
          (%screen-clear-dirty-cells back)
          (setf (renderer-rendered-generation renderer) back-generation)
          (if cursor
              (%snapshot-renderer-cursor renderer cursor)
              (setf (renderer-cursor renderer) nil))
          (values output diff-output-p)))))

(defun renderer-clear (renderer &key cell)
  "Reset RENDERER's back buffer to CELL (a template, character, or NIL for
blank), returning RENDERER. The change is emitted by the next RENDERER-RENDER."
  (%assert-renderer renderer)
  (screen-clear (renderer-screen renderer) :cell cell)
  renderer)

(defun renderer-invalidate (renderer)
  "Drop RENDERER's previous-frame snapshot and return RENDERER.

The next RENDERER-RENDER emits a full repaint. Use this after the terminal may
have been modified outside the renderer, such as after suspend/resume."
  (%assert-renderer renderer)
  (setf (renderer-front renderer) nil
        (renderer-cursor renderer) nil
        (renderer-rendered-generation renderer) nil)
  renderer)

(defun renderer-resize (renderer width height &key initial-cell)
  "Resize RENDERER to WIDTH by HEIGHT, returning RENDERER. The previous-frame snapshot is dropped so the next RENDERER-RENDER repaints in full, since a resized terminal cannot be updated by a diff."
  (%assert-renderer renderer)
  (screen-resize
    (renderer-screen renderer)
    width
    height
    :initial-cell
    initial-cell)
  (renderer-invalidate renderer)
  (setf (renderer-diff-plan renderer) (%make-screen-diff-plan (renderer-screen renderer)))
  renderer)
