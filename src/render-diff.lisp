(in-package #:cl-tty-kit)

(defun %cell-equal-p (left right)
  (and (char= (cell-char left) (cell-char right))
       ;; Cell styles are already normalized (see %NORMALIZE-CELL-STYLE), so
       ;; an EQUAL raw-style comparison answers the common case -- identical
       ;; or both-blank cells, the bulk of any diff -- without rebuilding
       ;; each cell's SGR code list. Differing raw styles can still render
       ;; identically (e.g. two distinct SGR-unsupported keywords both drop
       ;; out), so fall back to the semantic comparison only then.
       (or (equal (cell-style left) (cell-style right))
           (equal (%supported-cell-style-codes left)
                  (%supported-cell-style-codes right)))))

(defun %render-blank-cell-p (cell)
  (and (char= (cell-char cell) #\Space)
       (null (%supported-cell-style-codes cell))))

(defun %same-screen-dimensions-p (screen previous)
  (and previous
       (= (screen-width screen) (screen-width previous))
       (= (screen-height screen) (screen-height previous))))

(defun %row-blank-suffix-start (screen y)
  (do ((x (1- (screen-width screen)) (1- x))
       (start (screen-width screen)))
      ((< x 0) start)
    (if (%render-blank-cell-p (screen-cell screen x y))
        (setf start x)
        (return start))))

(defun %write-diff-run (screen previous start-x y stream)
  (do ((x start-x (1+ x)))
      ((>= x (screen-width screen)) (screen-width screen))
    (let ((current (screen-cell screen x y))
          (old (screen-cell previous x y)))
      (when (%cell-equal-p current old)
        (return x))
      (%write-cell current stream))))

(defun %collect-diff-run-output (screen previous start-x y)
  (let ((stream (make-string-output-stream)))
    (let ((next-x (%write-diff-run screen previous start-x y stream)))
      (values (get-output-stream-string stream)
              next-x))))

(defun %emit-diff-cursor (emit x y)
  (funcall emit `(:cursor ,(1+ y) ,(1+ x))))

(defun %emit-diff-clear-line (emit)
  (funcall emit '(:clear-line 0)))

(defun %emit-diff-run (screen previous x y emit)
  (multiple-value-bind (run-string next-x)
      (%collect-diff-run-output screen previous x y)
    (unless (> next-x x)
      (error "Diff run did not advance at (~D,~D)" x y))
    (%emit-diff-cursor emit x y)
    (funcall emit `(:string ,run-string))
    next-x))

(defun %render-parts-length (parts)
  (reduce #'+ parts :key #'length :initial-value 0))

(defun %render-command-length (command)
  ;; Sum each part's length directly instead of concatenating them into a
  ;; throwaway string via %RENDER-COMMAND-STRING: %PREFERRED-DIFF-COMMANDS
  ;; calls this once per command in both the full-screen and diff command
  ;; lists just to pick the smaller one, and the chosen list is rendered for
  ;; real afterwards -- so the old body paid for a full string build (and,
  ;; for a screen-sized command list, effectively a whole extra frame of
  ;; rendering) purely to throw the result away.
  (%render-parts-length (%render-command-parts command)))

(defun %screen-render-length (screen)
  (let ((length (+ (length (ansi-clear-screen))
                   (length (ansi-move-cursor 1 1)))))
    (loop for y from 0 below (screen-height screen) do
      (loop for x from 0 below (screen-width screen) do
        (incf length (%render-parts-length
                      (%cell-render-parts (screen-cell screen x y)))))
      (unless (%screen-last-row-p screen y)
        (incf length 1)))
    length))

(defun %render-commands-length (commands)
  (loop for command in commands
        sum (%render-command-length command)))

(defun %diff-render-commands (screen previous &key max-length)
  (block too-long
    (let ((length 0))
      (with-render-commands (emit finish)
        (flet ((emit-counted (command)
                 (let ((next-length (+ length (%render-command-length command))))
                   (when (and max-length (>= next-length max-length))
                     (return-from too-long (values nil next-length t)))
                   (setf length next-length)
                   (emit command))))
          (do ((y 0 (1+ y)))
              ((>= y (screen-height screen)))
            (let ((blank-suffix-start (%row-blank-suffix-start screen y)))
              (do ((x 0))
                  ((>= x (screen-width screen)))
                (let ((current (screen-cell screen x y))
                      (old (screen-cell previous x y)))
                  (cond
                    ((%cell-equal-p current old)
                     (incf x))
                    ((<= blank-suffix-start x)
                     (%emit-diff-cursor #'emit-counted x y)
                     (%emit-diff-clear-line #'emit-counted)
                     (setf x (screen-width screen)))
                    (t
                     (setf x (%emit-diff-run screen previous x y
                                             #'emit-counted))))))))
          (values (finish) length nil))))))

(defun %preferred-diff-commands (screen previous)
  (if (not (%same-screen-dimensions-p screen previous))
      (%screen-render-commands screen)
      (let ((screen-length (%screen-render-length screen)))
        (multiple-value-bind (diff-commands diff-length too-long-p)
            (%diff-render-commands screen previous :max-length screen-length)
          (cond
            (too-long-p
             (%screen-render-commands screen))
            ((null diff-commands)
             nil)
            ((< diff-length screen-length)
             diff-commands)
            (t
             (%screen-render-commands screen)))))))

(defun %frame-diff-render-commands (screen previous cursor previous-cursor)
  (let ((commands (%preferred-diff-commands screen previous))
        (cursor-commands (%cursor-render-commands cursor)))
    (if (and (null commands)
             previous-cursor
             (%cursor-equal-p cursor previous-cursor))
        commands
        (nconc commands
               cursor-commands))))
