(in-package #:cl-tty-kit)

(defun %input->string (input)
  (cond
    ((stringp input)
     input)
    ((and (vectorp input)
          (subtypep (array-element-type input) '(unsigned-byte 8)))
     (%utf8-octets-to-string input))
    ((vectorp input)
     (coerce input 'string))
    (t
     (error "Unsupported input type: ~S" (type-of input)))))

(defun decode-key-sequence (input &key (start 0))
  "Decode a single key sequence from INPUT starting at START.
Returns two values: a KEY-EVENT and the number of consumed characters."
  (declare (optimize (safety 0)))
  (let* ((string (%input->string input))
         (length (length string)))
    (when (< start length)
      (let ((ch (aref string start)))
        (cond
          ((char= ch #\Esc)
           (multiple-value-bind (event consumed)
               (%parse-esc-prefixed string start)
             (if event
                 (values event consumed)
                 (values (%key-event :special :escape nil) 1))))
          ((char= ch #\Rubout)
           (values (%key-event :special :backspace nil) 1))
          (t (%plain-key-event ch)))))))
