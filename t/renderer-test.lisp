(in-package #:cl-tty-kit/test)

(describe "make-renderer"
  (it "creates a renderer wrapping a screen of the given size"
    (let ((renderer (make-renderer 4 2)))
      (expect (renderer-width renderer) :to-be 4)
      (expect (renderer-height renderer) :to-be 2)
      (expect (renderer-screen renderer) :to-be-instance-of 'screen))))

(describe "renderer public API validation"
  (it "rejects a non-renderer argument"
    (expect-non-type-error (renderer-width :not-a-renderer))
    (expect-non-type-error (renderer-height :not-a-renderer))
    (expect-non-type-error (renderer-render :not-a-renderer))
    (expect-non-type-error (renderer-clear :not-a-renderer))
    (expect-non-type-error (renderer-resize :not-a-renderer 1 1)))
  (it "rejects a non-cursor :cursor argument"
    (expect-non-type-error (renderer-render (make-renderer 1 1) :cursor :not-a-cursor))))

(describe "renderer-render"
  (it "renders the initial screen, then only the diff, then nothing when unchanged"
    (let ((renderer (make-renderer 4 1)))
      (screen-write-string (renderer-screen renderer) 0 0 "Hi")
      (expect (renderer-render renderer) :to-equal (render-screen (renderer-screen renderer)))
      (expect (cl-tty-kit::renderer-rendered-generation renderer)
              :to-be (cl-tty-kit::screen-generation (renderer-screen renderer)))
      (expect (renderer-render renderer) :to-equal "")
      (let ((stream (make-string-output-stream)))
        (expect (renderer-render renderer :stream stream) :to-be stream)
        (expect (get-output-stream-string stream) :to-equal ""))
      (screen-write-string (renderer-screen renderer) 3 0 "!")
      (let ((out (renderer-render renderer)))
        (expect (search "!" out))
        (expect (search "i" out) :to-be-falsy))
      (expect (renderer-render renderer) :to-equal ""))))

(describe "renderer-render's cell-equality fast path"
  (it "skips %CELL-EQUAL-P entirely when nothing changed"
    (let ((renderer (make-renderer 80 24))
          (calls 0)
          (original (symbol-function 'cl-tty-kit::%cell-equal-p)))
      (renderer-render renderer)
      (unwind-protect
           (progn
             (setf (symbol-function 'cl-tty-kit::%cell-equal-p)
                   (lambda (&rest arguments) (incf calls) (apply original arguments)))
             (expect (renderer-render renderer) :to-equal "")
             (expect calls :to-be 0))
        (setf (symbol-function 'cl-tty-kit::%cell-equal-p) original)))))

(describe "renderer front-buffer snapshot reuse"
  (it "reuses the front buffer object across renders and its cell identities across no-op renders"
    (let ((renderer (make-renderer 2 1)))
      (renderer-render renderer)
      (let ((front (cl-tty-kit::renderer-front renderer)))
        (screen-put-cell (renderer-screen renderer) 0 0 #\x)
        (renderer-render renderer)
        (expect (cl-tty-kit::renderer-front renderer) :to-be front)
        (let ((equivalent (make-cell :char #\x)))
          (setf (aref (cl-tty-kit::screen-cells front) 0) equivalent)
          (expect (renderer-render renderer) :to-equal "")
          (expect (aref (cl-tty-kit::screen-cells (cl-tty-kit::renderer-front renderer)) 0)
                  :to-be equivalent))
        (expect (renderer-render renderer) :to-equal "")))))

(describe "renderer diff-plan reuse"
  (it "matches RENDER-DIFF's own output and updates the cached front buffer, including on clear-line"
    (let ((renderer (make-renderer 4 1)))
      (screen-write-string (renderer-screen renderer) 0 0 "ABCD")
      (renderer-render renderer)
      (screen-write-string (renderer-screen renderer) 1 0 "   ")
      (let ((expected (render-diff (renderer-screen renderer)
                                   (screen-copy (cl-tty-kit::renderer-front renderer))))
            (actual (renderer-render renderer)))
        (expect actual :to-equal expected)
        (expect (search (ansi-clear-line 0) actual)))
      ;; The clear-line sentinel must also update the cached front buffer.
      (expect (renderer-render renderer) :to-equal "")
      (screen-put-cell (renderer-screen renderer) 0 0 #\Z)
      (let ((expected (render-diff (renderer-screen renderer)
                                   (screen-copy (cl-tty-kit::renderer-front renderer)))))
        (expect (renderer-render renderer) :to-equal expected))))
  (it "chooses a full repaint for a dense update and still refreshes the front buffer in one bulk copy"
    (let ((renderer (make-renderer 80 24)))
      (renderer-render renderer)
      (screen-fill (renderer-screen renderer) #\X)
      (expect (renderer-render renderer) :to-equal (render-screen (renderer-screen renderer)))
      (expect (renderer-render renderer) :to-equal ""))))

(describe "renderer diff-plan capacity across a resize"
  (it "grows the reused diff-plan operations vector and keeps it stable afterward"
    (let ((renderer (make-renderer 1 1)))
      (renderer-render renderer)
      (renderer-resize renderer 8 1)
      (renderer-render renderer)
      (expect (array-total-size
               (cl-tty-kit::diff-plan-operations (cl-tty-kit::renderer-diff-plan renderer)))
              :to-be 16)
      (dolist (x '(0 2 4 6))
        (screen-put-cell (renderer-screen renderer) x 0 #\X))
      (renderer-render renderer)
      (expect (array-total-size
               (cl-tty-kit::diff-plan-operations (cl-tty-kit::renderer-diff-plan renderer)))
              :to-be 16)
      (screen-put-cell (renderer-screen renderer) 1 0 #\Y)
      (let ((expected (render-diff (renderer-screen renderer)
                                   (screen-copy (cl-tty-kit::renderer-front renderer)))))
        (expect (renderer-render renderer) :to-equal expected)))))

(describe "renderer row-generation-guided diff plans"
  (it "only marks the row a change touched as needing re-diffing"
    (let ((renderer (make-renderer 4 2)))
      (renderer-render renderer)
      (let ((previous-generation (cl-tty-kit::renderer-rendered-generation renderer)))
        (screen-put-cell (renderer-screen renderer) 1 1 #\x)
        (expect (aref (cl-tty-kit::screen-row-generations (renderer-screen renderer)) 0)
                :to-be-less-than-or-equal previous-generation)
        (expect (aref (cl-tty-kit::screen-row-generations (renderer-screen renderer)) 1)
                :to-be-greater-than previous-generation)
        (let ((expected (render-diff (renderer-screen renderer)
                                     (screen-copy (cl-tty-kit::renderer-front renderer)))))
          (expect (renderer-render renderer) :to-equal expected))))))

(describe "renderer cursor tracking"
  (it "renders the cursor escape once, then nothing while the cursor is unchanged"
    (let ((renderer (make-renderer 3 1))
          (cursor (make-cursor :x 1 :y 0)))
      (screen-write-string (renderer-screen renderer) 0 0 "ab")
      (expect (renderer-render renderer :cursor cursor)
              :to-equal (render-frame (renderer-screen renderer) cursor))
      (let ((snapshot (cl-tty-kit::renderer-cursor renderer)))
        (expect (renderer-render renderer :cursor cursor) :to-equal "")
        (expect (cl-tty-kit::renderer-cursor renderer) :to-be snapshot))
      ;; A caller-owned cursor is not the saved snapshot.
      (setf (cursor-x cursor) 2)
      (expect (length (renderer-render renderer :cursor cursor)) :to-be-greater-than 0)
      (expect (renderer-render renderer :cursor cursor) :to-equal "")))
  (it "re-emits the cursor escape when only the screen changed, even with unchanged cursor state"
    (let ((renderer (make-renderer 2 1))
          (cursor (make-cursor :x 1 :y 0)))
      (renderer-render renderer :cursor cursor)
      (screen-put-cell (renderer-screen renderer) 0 0 #\x)
      (renderer-render renderer)
      (expect (renderer-render renderer :cursor cursor) :to-equal (render-cursor cursor))))
  (it "combines the screen diff with the cursor escape when both changed"
    (let ((renderer (make-renderer 3 1))
          (cursor (make-cursor :x 1 :y 0)))
      (screen-write-string (renderer-screen renderer) 0 0 "ab")
      (renderer-render renderer :cursor cursor)
      (screen-put-cell (renderer-screen renderer) 0 0 #\z)
      (let* ((expected (render-frame-diff (renderer-screen renderer)
                                          (screen-copy (cl-tty-kit::renderer-front renderer))
                                          cursor
                                          :previous-cursor (cl-tty-kit::renderer-cursor renderer)))
             (actual (renderer-render renderer :cursor cursor)))
        ;; Screen output moves the terminal cursor, so the matching cursor must
        ;; be emitted again even though its logical state is unchanged.
        (expect actual :to-equal expected)
        (expect (search (render-cursor cursor) actual)))
      (expect (renderer-render renderer :cursor cursor) :to-equal ""))))

(describe "renderer-render :stream"
  (it "writes to the given stream and returns it"
    (let ((renderer (make-renderer 2 1))
          (stream (make-string-output-stream))
          (cursor (make-cursor :x 1 :y 0)))
      (screen-write-string (renderer-screen renderer) 0 0 "ab")
      (let ((expected (render-frame (renderer-screen renderer) cursor)))
        (expect (renderer-render renderer :stream stream :cursor cursor) :to-be stream)
        (expect (get-output-stream-string stream) :to-equal expected))
      (expect (renderer-render renderer :cursor cursor) :to-equal ""))))

(describe "renderer-clear and renderer-resize"
  (it "renderer-clear blanks the back buffer and returns the renderer"
    (let ((renderer (make-renderer 2 1)))
      (screen-write-string (renderer-screen renderer) 0 0 "ab")
      (renderer-render renderer)
      (expect (renderer-clear renderer) :to-be renderer)
      (expect (cell-char (screen-cell (renderer-screen renderer) 0 0)) :to-be #\Space)))
  (it "renderer-resize changes size, returns the renderer, and forces a full repaint next time"
    (let ((renderer (make-renderer 2 1)))
      (renderer-render renderer)
      (expect (renderer-resize renderer 3 1) :to-be renderer)
      (expect (renderer-width renderer) :to-be 3)
      (screen-write-string (renderer-screen renderer) 0 0 "x")
      (expect (renderer-render renderer) :to-equal (render-screen (renderer-screen renderer))))))
