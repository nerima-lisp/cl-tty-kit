(in-package #:cl-tty-kit)

(defmacro with-render-commands ((emit finish) &body body)
  `(let ((commands '()))
     (flet ((,emit (command)
              (push command commands))
            (,finish ()
              (nreverse commands)))
       ,@body)))

(defun %render-command-parts (command)
  (ecase (first command)
    (:string
     (list (second command)))
    (:cursor
     (list (ansi-move-cursor (second command)
                             (third command))))
    (:clear-line
     (list (ansi-clear-line (second command))))
    (:visibility
     (list (if (second command)
               (ansi-show-cursor)
               (ansi-hide-cursor))))
    (:cell
     (%cell-render-parts (second command)))
    (:newline
     (list (string #\Newline)))))

(defun %write-render-command (command stream)
  (dolist (part (%render-command-parts command) stream)
    (write-string part stream))
  stream)

(defun %write-render-commands (commands stream)
  (dolist (command commands stream)
    (%write-render-command command stream)))

(defun %render-command-string (command)
  (with-output-to-string (stream)
    (dolist (part (%render-command-parts command))
      (write-string part stream))))

(defun %render-commands-string (commands)
  (with-output-to-string (stream)
    (%write-render-commands commands stream)))

(defun %render-commands-output (commands stream)
  (if stream
      (%write-render-commands commands stream)
      (%render-commands-string commands)))

(defun %screen-last-row-p (screen y)
  (= y (1- (screen-height screen))))

(defun %emit-screen-row (screen y emit)
  (loop for x from 0 below (screen-width screen) do
    (funcall emit `(:cell ,(screen-cell screen x y))))
  (unless (%screen-last-row-p screen y)
    (funcall emit '(:newline))))

(defun %screen-render-commands (screen)
  (with-render-commands (emit finish)
    (emit `(:string ,(ansi-clear-screen)))
    (emit '(:cursor 1 1))
    (loop for y from 0 below (screen-height screen) do
      (%emit-screen-row screen y #'emit))
    (finish)))

(defun %cursor-render-commands (cursor)
  `((:cursor ,(1+ (cursor-y cursor)) ,(1+ (cursor-x cursor)))
    (:visibility ,(cursor-visible-p cursor))))

(defun %cursor-equal-p (left right)
  (and (= (cursor-x left) (cursor-x right))
       (= (cursor-y left) (cursor-y right))
       (eq (cursor-visible-p left) (cursor-visible-p right))))
