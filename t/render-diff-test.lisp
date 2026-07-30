(in-package #:cl-tty-kit/test)

(defun %screen-from-rows (&rest rows)
  (let* ((height (length rows))
         (width
        (if rows (length (first rows))
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
      ,@(mapcar
        (lambda (cell)
          (destructuring-bind (x y char &key style) cell
            `(screen-put-cell ,screen ,x ,y ,char :style ,style)))
        cells)
      ,screen)))

(defun %assert-render-contains-parts (output parts)
  (dolist (part parts)
    (expect (search part output))))

(defun %assert-render-output (output expected)
  (cond
    ((null expected) (expect output :to-equal ""))
    ((stringp expected) (expect output :to-equal expected))
    ((and (consp expected) (eq (first expected) :contains))
      (%assert-render-contains-parts output (rest expected)))
    (t (error "Unsupported render expectation: ~S" expected))))

(defun %assert-render-diff-output (new old expected)
  (%assert-render-output
    (render-diff new old)
    (if (eq expected :full-redraw) (render-screen new)
      expected)))

(defun %assert-render-diff-clear-line-output (new old expected-clear-line-p &optional required-style)
  (let ((diff (render-diff new old)))
    (expect (not (null (search (ansi-clear-line 0) diff))) :to-be expected-clear-line-p)
    (when required-style
      (expect (search required-style diff)))))

(describe "render-diff basic output"
  (it "emits the changed cell and a cursor-move escape for a single change"
    (let ((old (make-screen 2 1))
          (new (make-screen 2 1)))
      (screen-put-cell new 1 0 #\!)
      (let ((diff (render-diff new old)))
        (expect (search "!" diff))
        (expect (search (ansi-move-cursor 1 2) diff)))))
  (it "combined with render-cursor matches render-frame-diff, and covers only the changed region"
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
                     "Hi"))))
  (it "render-frame-diff writes directly to a stream and returns it"
    (let ((old (make-screen 2 1))
          (new (%screen-from-rows "Hi"))
          (cursor (make-cursor :x 1 :y 0))
          (stream (make-string-output-stream)))
      (expect-render-stream-output
       (stream (render-frame-diff new old cursor :stream stream))
       (%ansi-string (ansi-move-cursor 1 1)
                     "Hi"
                     (ansi-move-cursor 1 2)
                     (ansi-show-cursor))))))

(describe "render-diff/render-frame-diff against a nil or identical previous screen"
  (it "treats a nil previous screen as a full redraw, matching render-screen/render-frame"
    (let ((screen (%screen-from-rows "Hi")))
      (%assert-render-output (render-diff screen nil)
                             (render-screen screen))
      (let ((cursor (make-cursor :x 1 :y 0)))
        (%assert-render-output (render-frame-diff screen nil cursor)
                               (render-frame screen cursor)))))
  (it "emits nothing for two identical screens, whether via render-diff or render-frame-diff with an unmoved cursor"
    (let ((screen (%screen-from-rows "Hi")))
      (%assert-render-output (render-diff screen screen) nil)
      (let ((cursor (make-cursor :x 0 :y 0))
            (previous-cursor (make-cursor :x 0 :y 0)))
        (%assert-render-output (render-frame-diff screen screen cursor
                                                  :previous-cursor previous-cursor)
                               nil))))
  (it "still emits cursor commands via render-frame-diff when only the cursor's visibility changed"
    (let ((screen (%screen-from-rows "Hi"))
          (cursor (make-cursor :x 0 :y 0))
          (previous-cursor (make-cursor :x 0 :y 0 :visible nil)))
      (%assert-render-output (render-frame-diff screen screen cursor
                                                :previous-cursor previous-cursor)
                             (%ansi-string (ansi-move-cursor 1 1)
                                           (ansi-show-cursor)))))
  ;; An unchanged screen with a moved cursor still emits cursor commands --
  ;; X differing alone is enough, independent of Y or visibility.
  (it "still emits cursor commands via render-frame-diff when only the cursor's X changed"
    (let ((screen (%screen-from-rows "Hi"))
          (cursor (make-cursor :x 1 :y 0))
          (previous-cursor (make-cursor :x 0 :y 0)))
      (%assert-render-output (render-frame-diff screen screen cursor
                                                :previous-cursor previous-cursor)
                             (%ansi-string (ansi-move-cursor 1 2)
                                           (ansi-show-cursor)))))
  ;; Y differing alone (X and visibility equal) is likewise enough.
  (it "still emits cursor commands via render-frame-diff when only the cursor's Y changed"
    (let ((screen (%screen-from-rows "Hi" "Yo"))
          (cursor (make-cursor :x 0 :y 1))
          (previous-cursor (make-cursor :x 0 :y 0)))
      (%assert-render-output (render-frame-diff screen screen cursor
                                                :previous-cursor previous-cursor)
                             (%ansi-string (ansi-move-cursor 2 1)
                                           (ansi-show-cursor))))))

(describe "render-diff with styled cells"
  (dolist (style-case
           `((,(%screen-from-rows "X")
               ,(%screen-with-styled-cells "X" (0 0 #\X :style '(:bold)))
               (:contains ,(ansi-move-cursor 1 1) ,(ansi-bold) "X" ,(ansi-reset-style)))
             (,(%screen-with-styled-cells "X" (0 0 #\X :style '((:fg 196) (:bg 17))))
               ,(%screen-with-styled-cells "X" (0 0 #\X :style '((:bg 17) (:fg 196))))
               nil)
             (,(%screen-from-rows "X")
               ,(%screen-with-styled-cells "X" (0 0 #\X :style '((:fg 196) (:bg 17))))
               (:contains ,(ansi-move-cursor 1 1) "38;5;196;48;5;17m" "X" ,(ansi-reset-style)))
             (,(%screen-with-styled-cells "X" (0 0 #\X :style '(:no-such-modifier)))
               ,(%screen-from-rows "X")
               nil)
             (,(%screen-from-rows "X")
               ,(%screen-with-styled-cells "X" (0 0 #\X :style '(:blink)))
               (:contains
                 ,(ansi-move-cursor 1 1)
                 ,(format nil "~C[5m" #\Esc)
                 "X"
                 ,(ansi-reset-style)))))
    (destructuring-bind (old new expected) style-case
      (it (format nil "render-diff expects ~S" expected)
        (%assert-render-output (render-diff new old) expected)))))

(describe "control-character sanitization in rendered output"
  ;; #\Bell is printable on some implementations; code 7 is the C0 BEL.
  (dolist (char (list #\Esc (code-char 7) #\Rubout (code-char #x9b)))
    (it (format nil "sanitizes ~S to a blank space in both render-diff and render-screen" char)
      (let ((old (make-screen 1 1))
            (new (make-screen 1 1)))
        (screen-put-cell new 0 0 char)
        (%assert-render-output (render-diff new old)
                               (%ansi-string (ansi-move-cursor 1 1) " "))
        (%assert-render-output (render-screen new)
                               (%ansi-string (ansi-clear-screen)
                                             (ansi-move-cursor 1 1)
                                             " ")))))
  (it "sanitizes a control character while preserving its style"
    (let ((new (%screen-with-styled-cells "X" (0 0 #\Esc :style '(:bold))))
          (old (make-screen 1 1)))
      (%assert-render-output (render-diff new old)
                             (list :contains (ansi-bold) " " (ansi-reset-style))))))

(describe "render-diff across layout changes"
  (dolist (diff-case
           `((,(make-screen 2 1)
               ,(%screen-from-rows "AB")
               ,(%ansi-string (ansi-move-cursor 1 1) "AB"))
             (,(make-screen 1 1) ,(%screen-from-rows "OK") :full-redraw)
             (,(make-screen 2 2)
               ,(%screen-from-rows "A " " B")
               ,(%ansi-string (ansi-move-cursor 1 1) "A" (ansi-move-cursor 2 2) "B"))
             (,(make-screen 5 1)
               ,(%screen-from-rows "A   B")
               ,(%ansi-string (ansi-move-cursor 1 1) "A" (ansi-move-cursor 1 5) "B"))))
    (destructuring-bind (old new expected) diff-case
      (it (format nil "render-diff expects ~S" expected)
        (%assert-render-diff-output new old expected)))))

(describe "render-diff's clear-line (EL) optimization"
  (dolist (clear-case
           `((,(%screen-from-rows "HELLO") ,(%screen-from-rows "HE   ") t nil)
             (,(%screen-from-rows "ABC") ,(%screen-from-rows "   ") t nil)
             (,(%screen-from-rows "ABC")
               ,(%screen-with-styled-cells
                 "A  "
                 (1 0 #\Space :style '(:underline))
                 (2 0 #\Space :style '(:underline)))
               nil
               ,(format nil "~C[4m" #\Esc))
             (,(%screen-from-rows "ABC")
               ,(%screen-with-styled-cells
                 "A  "
                 (1 0 #\Space :style '((:fg 196)))
                 (2 0 #\Space :style '((:fg 196))))
               nil
               ,(format nil "~C[38;5;196m" #\Esc))))
    (destructuring-bind (old new expect-clear-line-p required-style) clear-case
      (it (format nil "expect-clear-line-p=~S required-style=~S" expect-clear-line-p required-style)
        (%assert-render-diff-clear-line-output
         new
         old
         expect-clear-line-p
         required-style))))
  (it "still uses clear-line when the changed cells carry only an unsupported style modifier"
    (let ((old (%screen-from-rows "ABC"))
          (new (%screen-with-styled-cells
                "A  "
                (1 0 #\Space :style '(:no-such-modifier))
                (2 0 #\Space :style '(:no-such-modifier)))))
      (%assert-render-diff-clear-line-output new old t))))

(describe "render-diff falling back to a full redraw or writing to a stream"
  (it "renders a dense change as a full redraw, matching render-screen, and can write that to a stream"
    (let ((old (make-screen 10 4))
          (new (make-screen 10 4))
          (stream (make-string-output-stream)))
      (loop for y from 0 below 4
            do (loop for x from 0 below 10 by 2
              do (screen-put-cell new x y #\X)))
      (expect (render-screen new) :to-equal (render-diff new old))
      (expect-render-stream-output
       (stream (render-diff new old stream))
       (render-screen new))))
  (it "writes a sparse diff to a stream, matching the non-stream form"
    (let ((old (make-screen 6 1))
          (new (make-screen 6 1))
          (stream (make-string-output-stream)))
      (screen-put-cell new 2 0 #\X)
      (expect-render-stream-output
       (stream (render-diff new old stream))
       (render-diff new old)))))

(describe "render-frame-diff full output"
  (it "combines the screen diff with the cursor escape for a from-scratch previous state"
    (let ((old (make-screen 2 1))
          (new (%screen-from-rows "OK"))
          (cursor (make-cursor :x 0 :y 0))
          (previous-cursor (make-cursor :x 0 :y 0)))
      (expect (render-frame-diff new old cursor :previous-cursor previous-cursor)
              :to-equal (%ansi-string
                         (ansi-move-cursor 1 1)
                         "OK"
                         (ansi-move-cursor 1 1)
                         (ansi-show-cursor))))))

(describe "render-diff's %diff-cursor-length matches ansi-move-cursor's length"
  (dolist (coordinate '(0 8 9 98 99 998 999))
    (it (format nil "at coordinate ~D" coordinate)
      (expect (cl-tty-kit::%diff-cursor-length coordinate coordinate)
              :to-be (length (ansi-move-cursor (1+ coordinate) (1+ coordinate)))))))

(describe "%screen-render-length and %screen-render-length-exceeds-p"
  (it "matches render-screen's actual output length and its exceeds-p boundary"
    (let ((screen (make-screen 2 3)))
      (expect (cl-tty-kit::%screen-render-length screen) :to-be (length (render-screen screen)))
      (expect (cl-tty-kit::%screen-render-length-exceeds-p screen 17))
      (expect (not (cl-tty-kit::%screen-render-length-exceeds-p screen 18))))))

(describe "the reusable diff-plan primitives"
  (it "an explicit plan computed via %plan-diff-length matches render-diff, is reusable by %render-diff-output, and clears when unchanged since its own generation"
    (let ((old (make-screen 80 24))
          (new (make-screen 80 24)))
      (screen-put-cell new 0 0 #\X)
      (screen-put-cell new 79 23 #\Y)
      (let ((plan (cl-tty-kit::%make-screen-diff-plan new)))
        (let ((diff-length (cl-tty-kit::%plan-diff-length new old plan)))
          (expect diff-length :to-be (length (render-diff new old)))
          (expect (cl-tty-kit::%render-diff-output new old nil plan)
                  :to-equal (render-diff new old)))
        (expect (plusp (fill-pointer (cl-tty-kit::diff-plan-operations plan))))
        (expect (zerop (cl-tty-kit::%plan-diff-length
                        new old plan (cl-tty-kit::screen-generation new))))
        (expect (zerop (fill-pointer (cl-tty-kit::diff-plan-operations plan))))))))

(describe "%diff-render-length's length estimate"
  (it "matches render-diff's actual length and reports too-long-p correctly, before and after a further change"
    (let ((old (make-screen 80 24))
          (new (make-screen 80 24)))
      (multiple-value-bind (estimated-length too-long-p)
          (cl-tty-kit::%diff-render-length new old (cl-tty-kit::%screen-render-length new))
        (expect (not too-long-p))
        (expect estimated-length :to-be (length (render-diff new old))))
      (screen-put-cell new 79 23 #\X)
      (multiple-value-bind (estimated-length too-long-p)
          (cl-tty-kit::%diff-render-length new old (cl-tty-kit::%screen-render-length new))
        (expect (not too-long-p))
        (expect estimated-length :to-be (length (render-diff new old)))))))
