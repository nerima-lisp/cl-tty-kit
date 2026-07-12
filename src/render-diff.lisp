(in-package #:cl-tty-kit)

(defun %cell-equal-p (left right)
  (and (char= (cell-char left) (cell-char right))
       (equal (%supported-cell-style-codes left)
              (%supported-cell-style-codes right))))

(defun %render-blank-cell-p (cell)
  (and (char= (cell-char cell) #\Space)
       (null (%supported-cell-style-codes cell))))

(defun %same-screen-dimensions-p (screen previous)
  (and previous
       (= (screen-width screen) (screen-width previous))
       (= (screen-height screen) (screen-height previous))))

(defun %clear-to-end-of-line-p (screen start-x y)
  (do ((x start-x (1+ x)))
      ((>= x (screen-width screen)) t)
    (unless (%render-blank-cell-p (screen-cell screen x y))
      (return nil))))

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
  (emit `(:cursor ,(1+ y) ,(1+ x))))

(defun %emit-diff-clear-line (emit)
  (emit '(:clear-line 0)))

(defun %emit-diff-run (screen previous x y emit)
  (multiple-value-bind (run-string next-x)
      (%collect-diff-run-output screen previous x y)
    (unless (> next-x x)
      (error "Diff run did not advance at (~D,~D)" x y))
    (%emit-diff-cursor emit x y)
    (emit `(:string ,run-string))
    next-x))

(defun %diff-render-commands (screen previous)
  (with-render-commands (emit finish)
    (do ((y 0 (1+ y)))
        ((>= y (screen-height screen)) (finish))
      (do ((x 0))
          ((>= x (screen-width screen)))
        (let ((current (screen-cell screen x y))
              (old (screen-cell previous x y)))
          (cond
            ((%cell-equal-p current old)
             (incf x))
            ((%clear-to-end-of-line-p screen x y)
             (%emit-diff-cursor emit x y)
             (%emit-diff-clear-line emit)
             (setf x (screen-width screen)))
            (t
             (setf x (%emit-diff-run screen previous x y emit)))))))
    (finish)))

(defun %render-command-length (command)
  (length (%render-command-string command)))

(defun %render-commands-length (commands)
  (loop for command in commands
        sum (%render-command-length command)))

(defun %preferred-diff-commands (screen previous)
  (let ((screen-commands (%screen-render-commands screen)))
    (if (not (%same-screen-dimensions-p screen previous))
        screen-commands
        (let ((diff-commands (%diff-render-commands screen previous)))
          (cond
            ((null diff-commands)
             nil)
            (t
             (let ((screen-length (%render-commands-length screen-commands)))
               (if (< (%render-commands-length diff-commands)
                      screen-length)
                   diff-commands
                   screen-commands))))))))

(defun %frame-diff-render-commands (screen previous cursor previous-cursor)
  (let ((commands (%preferred-diff-commands screen previous))
        (cursor-commands (%cursor-render-commands cursor)))
    (if (and (null commands)
             previous-cursor
             (%cursor-equal-p cursor previous-cursor))
        commands
        (append commands
                cursor-commands))))
