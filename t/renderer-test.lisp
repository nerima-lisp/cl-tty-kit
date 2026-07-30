(in-package #:cl-tty-kit/test)

(defun %test-renderer-basics ()
  (let ((renderer (make-renderer 4 2)))
    (is (= 4 (renderer-width renderer)))
    (is (= 2 (renderer-height renderer)))
    (is (typep (renderer-screen renderer) (quote screen)))))

(defun %test-renderer-public-validation ()
  (signals-non-type-error (renderer-width :not-a-renderer))
  (signals-non-type-error (renderer-height :not-a-renderer))
  (signals-non-type-error (renderer-render :not-a-renderer))
  (signals-non-type-error (renderer-clear :not-a-renderer))
  (signals-non-type-error (renderer-resize :not-a-renderer 1 1))
  (signals-non-type-error
    (renderer-render (make-renderer 1 1) :cursor :not-a-cursor)))

(defun %test-renderer-render () (let ((renderer (make-renderer 4 1))) (screen-write-string (renderer-screen renderer) 0 0 "Hi") (is (string= (render-screen (renderer-screen renderer)) (renderer-render renderer))) (is (= (cl-tty-kit::screen-generation (renderer-screen renderer)) (cl-tty-kit::renderer-rendered-generation renderer))) (is (string= "" (renderer-render renderer))) (let ((stream (make-string-output-stream))) (is (eq stream (renderer-render renderer :stream stream))) (is (string= "" (get-output-stream-string stream)))) (screen-write-string (renderer-screen renderer) 3 0 "!") (let ((out (renderer-render renderer))) (is (search "!" out)) (is (not (search "i" out)))) (is (string= "" (renderer-render renderer)))))

(defun %test-renderer-snapshot-reuse ()
  (let ((renderer (make-renderer 2 1)))
    (renderer-render renderer)
    (let ((front (cl-tty-kit::renderer-front renderer)))
      (screen-put-cell (renderer-screen renderer) 0 0 #\x)
      (renderer-render renderer)
      (is (eq front (cl-tty-kit::renderer-front renderer)))
      (let ((equivalent (make-cell :char #\x)))
        (setf (aref (cl-tty-kit::screen-cells front) 0) equivalent)
        (is (string= "" (renderer-render renderer)))
        (is
         (eq equivalent
             (aref
              (cl-tty-kit::screen-cells (cl-tty-kit::renderer-front renderer))
              0))))
      (is (string= "" (renderer-render renderer))))))

(defun %test-renderer-reused-diff-plan ()
  (let ((renderer (make-renderer 4 1)))
    (screen-write-string (renderer-screen renderer) 0 0 "ABCD")
    (renderer-render renderer)
    (screen-write-string (renderer-screen renderer) 1 0 "   ")
    (let ((expected
            (render-diff
              (renderer-screen renderer)
              (screen-copy (cl-tty-kit::renderer-front renderer))))
          (actual (renderer-render renderer)))
      (is (string= expected actual))
      (is (search (ansi-clear-line 0) actual)))
    ;; The clear-line sentinel must also update the cached front buffer.
    (is (string= "" (renderer-render renderer)))
    (screen-put-cell (renderer-screen renderer) 0 0 #\Z)
    (is
      (string=
        (render-diff
          (renderer-screen renderer)
          (screen-copy (cl-tty-kit::renderer-front renderer)))
        (renderer-render renderer))))
  (let ((renderer (make-renderer 80 24)))
    (renderer-render renderer)
    (screen-fill (renderer-screen renderer) #\X)
    ;; A dense update chooses a full repaint and still refreshes the reusable
    ;; front buffer in one bulk copy.
    (is
      (string=
        (render-screen (renderer-screen renderer))
        (renderer-render renderer)))
    (is (string= "" (renderer-render renderer)))))

(defun %test-renderer-resized-diff-plan-capacity ()
  (let ((renderer (make-renderer 1 1)))
    (renderer-render renderer)
    (renderer-resize renderer 8 1)
    (renderer-render renderer)
    (let ((operations
           (cl-tty-kit::diff-plan-operations
            (cl-tty-kit::renderer-diff-plan renderer))))
      (is (= 16 (array-total-size operations))))
    (dolist (x (quote (0 2 4 6)))
      (screen-put-cell (renderer-screen renderer) x 0 #\X))
    (renderer-render renderer)
    (is
     (= 16
        (array-total-size
         (cl-tty-kit::diff-plan-operations
          (cl-tty-kit::renderer-diff-plan renderer)))))
    (screen-put-cell (renderer-screen renderer) 1 0 #\Y)
    (is
     (string=
      (render-diff
       (renderer-screen renderer)
       (screen-copy (cl-tty-kit::renderer-front renderer)))
      (renderer-render renderer)))))

(defun %test-renderer-cursor ()
  (let ((renderer (make-renderer 3 1))
        (cursor (make-cursor :x 1 :y 0)))
    (screen-write-string (renderer-screen renderer) 0 0 "ab")
    (is
      (string=
        (render-frame (renderer-screen renderer) cursor)
        (renderer-render renderer :cursor cursor)))
    (let ((snapshot (cl-tty-kit::renderer-cursor renderer)))
      (is (string= "" (renderer-render renderer :cursor cursor)))
      (is (eq snapshot (cl-tty-kit::renderer-cursor renderer))))
    ;; A caller-owned cursor is not the saved snapshot.
    (setf (cursor-x cursor) 2)
    (is (plusp (length (renderer-render renderer :cursor cursor))))
    (is (string= "" (renderer-render renderer :cursor cursor)))))

(defun %test-renderer-cursor-state-transitions ()
  (let ((renderer (make-renderer 2 1))
        (cursor (make-cursor :x 1 :y 0)))
    (renderer-render renderer :cursor cursor)
    (screen-put-cell (renderer-screen renderer) 0 0 #\x)
    (renderer-render renderer)
    (is (string= (render-cursor cursor) (renderer-render renderer :cursor cursor))))
  (let ((renderer (make-renderer 3 1))
        (cursor (make-cursor :x 1 :y 0)))
    (screen-write-string (renderer-screen renderer) 0 0 "ab")
    (renderer-render renderer :cursor cursor)
    (screen-put-cell (renderer-screen renderer) 0 0 #\z)
    (let* ((expected
             (render-frame-diff
               (renderer-screen renderer)
               (screen-copy (cl-tty-kit::renderer-front renderer))
               cursor
               :previous-cursor
               (cl-tty-kit::renderer-cursor renderer)))
           (actual (renderer-render renderer :cursor cursor)))
      ;; Screen output moves the terminal cursor, so the matching cursor must
      ;; be emitted again even though its logical state is unchanged.
      (is (string= expected actual))
      (is (search (render-cursor cursor) actual)))
    (is (string= "" (renderer-render renderer :cursor cursor)))))

(defun %test-renderer-stream ()
  (let ((renderer (make-renderer 2 1))
        (stream (make-string-output-stream))
        (cursor (make-cursor :x 1 :y 0)))
    (screen-write-string (renderer-screen renderer) 0 0 "ab")
    (let ((expected (render-frame (renderer-screen renderer) cursor)))
      (is (eq stream (renderer-render renderer :stream stream :cursor cursor)))
      (is (string= expected (get-output-stream-string stream))))
    (is (string= "" (renderer-render renderer :cursor cursor)))))

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

(progn
  (defun %test-renderer-generation-fast-path ()
    (let ((renderer (make-renderer 80 24))
          (calls 0)
          (original (symbol-function (quote cl-tty-kit::%cell-equal-p))))
      (renderer-render renderer)
      (unwind-protect
           (progn
             (setf (symbol-function (quote cl-tty-kit::%cell-equal-p))
                   (lambda (&rest arguments)
                     (incf calls)
                     (apply original arguments)))
             (is (string= "" (renderer-render renderer)))
             (is (zerop calls)))
        (setf (symbol-function (quote cl-tty-kit::%cell-equal-p)) original))))

  (defun %test-renderer-row-generation-diff-plan ()
    (let ((renderer (make-renderer 4 2)))
      (renderer-render renderer)
      (let ((previous-generation (cl-tty-kit::renderer-rendered-generation renderer)))
        (screen-put-cell (renderer-screen renderer) 1 1 #\x)
        (is (<= (aref (cl-tty-kit::screen-row-generations (renderer-screen renderer)) 0)
                previous-generation))
        (is (> (aref (cl-tty-kit::screen-row-generations (renderer-screen renderer)) 1)
               previous-generation))
        (is (string= (render-diff (renderer-screen renderer)
                                  (screen-copy (cl-tty-kit::renderer-front renderer)))
                     (renderer-render renderer))))))

  (defun test-renderer ()
    (%test-renderer-basics)
    (%test-renderer-public-validation)
    (%test-renderer-render)
    (%test-renderer-generation-fast-path)
    (%test-renderer-snapshot-reuse)
    (%test-renderer-reused-diff-plan)
    (%test-renderer-resized-diff-plan-capacity)
    (%test-renderer-row-generation-diff-plan)
    (%test-renderer-cursor)
    (%test-renderer-cursor-state-transitions)
    (%test-renderer-stream)
    (%test-renderer-clear-resize)
    t))
