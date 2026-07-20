(in-package #:cl-tty-kit/test)

(defun %test-renderer-basics ()
  (let ((renderer (make-renderer 4 2)))
    (is (= 4 (renderer-width renderer)))
    (is (= 2 (renderer-height renderer)))
    (is (typep (renderer-screen renderer) (quote screen)))))

(defun %signals-non-type-error (thunk)
  (handler-case
      (progn
        (funcall thunk)
        (is nil))
    (type-error (condition)
      (declare (ignore condition))
      (is nil))
    (error (condition)
      (declare (ignore condition))
      (is t))))

(defun %test-renderer-public-validation ()
  (%signals-non-type-error
   (lambda () (renderer-width :not-a-renderer)))
  (%signals-non-type-error
   (lambda () (renderer-height :not-a-renderer)))
  (%signals-non-type-error
   (lambda () (renderer-render :not-a-renderer)))
  (%signals-non-type-error
   (lambda () (renderer-clear :not-a-renderer)))
  (%signals-non-type-error
   (lambda () (renderer-resize :not-a-renderer 1 1)))
  (%signals-non-type-error
   (lambda () (renderer-render (make-renderer 1 1)
                               :cursor :not-a-cursor))))

(defun %test-renderer-render ()
  (let ((renderer (make-renderer 4 1)))
    ;; The first render has no prior frame, so it repaints in full.
    (screen-write-string (renderer-screen renderer) 0 0 "Hi")
    (is (string= (render-screen (renderer-screen renderer))
                 (renderer-render renderer)))
    ;; An unchanged frame emits nothing.
    (is (string= "" (renderer-render renderer)))
    ;; A single changed cell emits only that change.
    (screen-write-string (renderer-screen renderer) 3 0 "!")
    (let ((out (renderer-render renderer)))
      ;; Only the changed cell is emitted -- not the untouched "Hi". (Avoid
      ;; matching "H", which is the CUP escape's terminating byte.)
      (is (search "!" out))
      (is (not (search "i" out))))
    ;; ...and settles back to empty.
    (is (string= "" (renderer-render renderer)))))

(defun %test-renderer-cursor ()
  (let ((renderer (make-renderer 3 1))
        (cursor (make-cursor :x 1 :y 0)))
    (screen-write-string (renderer-screen renderer) 0 0 "ab")
    (is (string= (render-frame (renderer-screen renderer) cursor)
                 (renderer-render renderer :cursor cursor)))))

(defun %test-renderer-stream ()
  (let ((renderer (make-renderer 2 1))
        (stream (make-string-output-stream)))
    (screen-write-string (renderer-screen renderer) 0 0 "ab")
    (is (eq stream (renderer-render renderer :stream stream)))
    (is (string= (render-screen (renderer-screen renderer))
                 (get-output-stream-string stream)))))

(defun %test-renderer-clear-resize ()
  ;; RENDERER-CLEAR blanks the back buffer.
  (let ((renderer (make-renderer 2 1)))
    (screen-write-string (renderer-screen renderer) 0 0 "ab")
    (renderer-render renderer)
    (is (eq renderer (renderer-clear renderer)))
    (is (char= #\Space (cell-char (screen-cell (renderer-screen renderer) 0 0)))))
  ;; RENDERER-RESIZE changes size and forces a full repaint next time.
  (let ((renderer (make-renderer 2 1)))
    (renderer-render renderer)
    (is (eq renderer (renderer-resize renderer 3 1)))
    (is (= 3 (renderer-width renderer)))
    (screen-write-string (renderer-screen renderer) 0 0 "x")
    (is (string= (render-screen (renderer-screen renderer))
                 (renderer-render renderer)))))

(defun test-renderer ()
  (%test-renderer-basics)
  (%test-renderer-public-validation)
  (%test-renderer-render)
  (%test-renderer-cursor)
  (%test-renderer-stream)
  (%test-renderer-clear-resize)
  t)
