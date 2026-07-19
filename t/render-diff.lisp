(in-package #:cl-tty-kit/test)

(defun %screen-from-rows (&rest rows)
  (let* ((height (length rows))
         (width (if rows
                    (length (first rows))
                    0))
         (screen (make-screen width height)))
    (loop for row in rows
          for y from 0
          do (loop for char across row
                   for x from 0
                   unless (char= char #\Space)
                     do (screen-put-cell screen x y char)))
    screen))

(defmacro %screen-with-styled-cells (row &rest cells)
  "Build a screen from ROW, then paint each literal (X Y CHAR &KEY STYLE) cell.
CELLS are literal specifications, so callers write them inline without quoting."
  (let ((screen (gensym "SCREEN")))
    `(let ((,screen (%screen-from-rows ,row)))
       ,@(mapcar (lambda (cell)
                   (destructuring-bind (x y char &key style) cell
                     `(screen-put-cell ,screen ,x ,y ,char :style ,style)))
                 cells)
       ,screen)))

(defun %assert-render-contains-parts (output parts)
  (dolist (part parts)
    (is (search part output))))

(defun %assert-render-output (output expected)
  (cond
    ((null expected)
     (is (string= "" output)))
    ((stringp expected)
     (is (string= expected output)))
    ((and (consp expected)
          (eq (first expected) :contains))
     (%assert-render-contains-parts output (rest expected)))
    (t
     (error "Unsupported render expectation: ~S" expected))))

(defun %assert-render-diff-output (new old expected)
  (%assert-render-output (render-diff new old)
                         (if (eq expected :full-redraw)
                             (render-screen new)
                             expected)))

(defun %assert-render-diff-clear-line-output (new old expected-clear-line-p
                                               &optional required-style)
  (let ((diff (render-diff new old)))
    (is (eql expected-clear-line-p
             (not (null (search (ansi-clear-line 0) diff)))))
    (when required-style
      (is (search required-style diff)))))

(defun %test-render-diff-basic-output-cases ()
  (let ((old (make-screen 2 1))
        (new (make-screen 2 1)))
    (screen-put-cell new 1 0 #\!)
    (let ((diff (render-diff new old)))
      (is (search "!" diff))
      (is (search (ansi-move-cursor 1 2) diff))))
  (let ((old (make-screen 2 1))
        (new (%screen-from-rows "Hi"))
        (cursor (make-cursor :x 1 :y 0)))
    (%assert-render-output
     (%ansi-string (render-diff new old)
                   (render-cursor cursor))
     (%ansi-string (ansi-move-cursor 1 1)
                   "Hi"
                   (ansi-move-cursor 1 2)
                   (ansi-show-cursor)))
    (%assert-render-diff-output
     new old
     (%ansi-string (ansi-move-cursor 1 1)
                   "Hi")))
  (let ((old (make-screen 2 1))
        (new (%screen-from-rows "Hi"))
        (cursor (make-cursor :x 1 :y 0))
        (stream (make-string-output-stream)))
    (%assert-render-stream-output
     (stream (render-frame-diff new old cursor :stream stream))
     (%ansi-string (ansi-move-cursor 1 1)
                   "Hi"
                   (ansi-move-cursor 1 2)
                   (ansi-show-cursor))))
  (let ((screen (%screen-from-rows "Hi")))
    (%assert-render-output (render-diff screen nil)
                           (render-screen screen))
    (let ((cursor (make-cursor :x 1 :y 0)))
      (%assert-render-output (render-frame-diff screen nil cursor)
                             (render-frame screen cursor)))
    (%assert-render-output (render-diff screen screen) nil)
    (let ((cursor (make-cursor :x 0 :y 0))
          (previous-cursor (make-cursor :x 0 :y 0)))
      (%assert-render-output (render-frame-diff screen screen cursor
                                                :previous-cursor previous-cursor)
                             nil))
    (let ((cursor (make-cursor :x 0 :y 0))
          (previous-cursor (make-cursor :x 0 :y 0 :visible nil)))
      (%assert-render-output (render-frame-diff screen screen cursor
                                                :previous-cursor previous-cursor)
                             (%ansi-string (ansi-move-cursor 1 1)
                                           (ansi-show-cursor))))))

(defun %test-render-diff-style-cases ()
  (do-test-case-bind
      (style-case
       `((,(%screen-from-rows "X")
          ,(%screen-with-styled-cells "X" (0 0 #\X :style '(:bold)))
          (:contains ,(ansi-move-cursor 1 1) ,(ansi-bold) "X" ,(ansi-reset-style)))
         (,(%screen-with-styled-cells "X" (0 0 #\X :style '((:fg 196) (:bg 17))))
          ,(%screen-with-styled-cells "X" (0 0 #\X :style '((:bg 17) (:fg 196))))
          nil)
         (,(%screen-from-rows "X")
          ,(%screen-with-styled-cells "X" (0 0 #\X :style '((:fg 196) (:bg 17))))
          (:contains ,(ansi-move-cursor 1 1) "38;5;196;48;5;17m" "X" ,(ansi-reset-style)))
         (,(%screen-with-styled-cells "X" (0 0 #\X :style '(:blink)))
          ,(%screen-from-rows "X")
          nil))
       (old new expected))
    (%assert-render-output (render-diff new old) expected)))

(defun %test-render-diff-layout-cases ()
  (do-test-case-bind
      (diff-case
        `((,(make-screen 2 1)
          ,(%screen-from-rows "AB")
          ,(%ansi-string (ansi-move-cursor 1 1) "AB"))
         (,(make-screen 1 1)
          ,(%screen-from-rows "OK")
          :full-redraw)
         (,(make-screen 2 2)
          ,(%screen-from-rows "A " " B")
          ,(%ansi-string (ansi-move-cursor 1 1)
                         "A"
                         (ansi-move-cursor 2 2)
                         "B"))
         (,(make-screen 5 1)
          ,(%screen-from-rows "A   B")
          ,(%ansi-string (ansi-move-cursor 1 1)
                         "A"
                         (ansi-move-cursor 1 5)
                         "B")))
       (old new expected))
    (%assert-render-diff-output new old expected)))

(defun %test-render-diff-clear-line-cases ()
  (do-test-case-bind
      (clear-case
       `((,(%screen-from-rows "HELLO")
          ,(%screen-from-rows "HE   ")
          t nil)
         (,(%screen-from-rows "ABC")
          ,(%screen-from-rows "   ")
          t nil)
         (,(%screen-from-rows "ABC")
          ,(%screen-with-styled-cells "A  "
             (1 0 #\Space :style '(:underline))
             (2 0 #\Space :style '(:underline)))
          nil ,(format nil "~C[4m" #\Esc))
         (,(%screen-from-rows "ABC")
          ,(%screen-with-styled-cells "A  "
             (1 0 #\Space :style '((:fg 196)))
             (2 0 #\Space :style '((:fg 196))))
          nil ,(format nil "~C[38;5;196m" #\Esc)))
       (old new expect-clear-line-p required-style))
    (%assert-render-diff-clear-line-output new old
                                           expect-clear-line-p
                                           required-style)))

(defun %test-render-diff-stream-output-cases ()
  (let ((old (make-screen 10 4))
        (new (make-screen 10 4))
        (stream (make-string-output-stream)))
    (loop for y from 0 below 4 do
      (loop for x from 0 below 10 by 2 do
        (screen-put-cell new x y #\X)))
    (is (string= (render-screen new)
                 (render-diff new old)))
    (%assert-render-stream-output (stream (render-diff new old stream))
                                  (render-screen new))))

(defun %test-render-diff-frame-output-cases ()
  (let ((old (make-screen 2 1))
        (new (%screen-from-rows "OK"))
        (cursor (make-cursor :x 0 :y 0))
        (previous-cursor (make-cursor :x 0 :y 0)))
    (is (string= (%ansi-string (ansi-move-cursor 1 1)
                               "OK"
                               (ansi-move-cursor 1 1)
                               (ansi-show-cursor))
                 (render-frame-diff new old cursor
                                    :previous-cursor previous-cursor))))
  t)

(defun test-render-diff ()
  (%test-render-diff-basic-output-cases)
  (%test-render-diff-style-cases)
  (%test-render-diff-layout-cases)
  (%test-render-diff-clear-line-cases)
  (%test-render-diff-stream-output-cases)
  (%test-render-diff-frame-output-cases)
  t)
