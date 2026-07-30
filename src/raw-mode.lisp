(in-package #:cl-tty-kit)

(defvar *raw-mode-states* nil)

(defvar *raw-mode-tcsetattr-function* nil)

#+sb-thread
(defvar *raw-mode-states-lock*
  (sb-thread:make-mutex :name "cl-tty-kit raw-mode states"))

(defmacro %with-raw-mode-states-lock (&body body)
  "Serialize a raw-mode state transition (check-then-act on
*RAW-MODE-STATES* plus the TCGETATTR/TCSETATTR calls that accompany it)
against other threads sharing the same process. Raw-mode transitions are
infrequent, so one global lock -- rather than one per FD -- keeps this
simple without a measurable cost."
  #+sb-thread
  `(sb-thread:with-mutex (*raw-mode-states-lock*) ,@body)
  #-sb-thread
  `(progn ,@body))

(define-validating-assert %assert-raw-mode-fd (fd)
  (and (integerp fd) (not (minusp fd)))
  "Raw mode FD must be a non-negative integer, got ~S." fd)

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
