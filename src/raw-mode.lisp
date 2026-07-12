(in-package #:cl-tty-kit)

(defvar *raw-mode-states* nil)

(defvar *raw-mode-tcsetattr-function* nil)

(defmacro define-unsupported-raw-mode-operation (name)
  `(defun ,name (&optional (fd 0))
     "Signal that raw mode is unsupported on this implementation."
     (declare (ignore fd))
     (unsupported :raw-mode)))

(defun %signal-raw-mode-operation-failed (operation fd reason)
  (error 'raw-mode-operation-failed
         :operation operation
         :fd fd
         :reason reason))

(defun %raw-mode-state (fd)
  (assoc fd *raw-mode-states* :test #'eql))

(defun %raw-mode-state-depth (state)
  (getf (cdr state) :depth))

(defun %raw-mode-state-snapshot (state)
  (getf (cdr state) :snapshot))

(defun %set-raw-mode-state (fd snapshot depth)
  (let ((state (%raw-mode-state fd)))
    (if state
        (setf (getf (cdr state) :snapshot) snapshot
              (getf (cdr state) :depth) depth)
        (push (cons fd (list :snapshot snapshot :depth depth))
              *raw-mode-states*))
    depth))

(defun %remove-raw-mode-state (fd)
  (setf *raw-mode-states*
        (delete fd *raw-mode-states* :key #'car :test #'eql)))

(defmacro with-raw-mode ((&optional (fd 0)) &body body)
  "Execute BODY with raw mode enabled for FD when supported."
  (let ((enabled (gensym "ENABLED")))
    `(let ((,enabled nil))
       (unwind-protect
            (when (setf ,enabled (enable-raw-mode ,fd))
              ,@body)
         (when ,enabled
           (disable-raw-mode ,fd))))))

#-sbcl
(define-unsupported-raw-mode-operation enable-raw-mode)

#-sbcl
(define-unsupported-raw-mode-operation disable-raw-mode)
