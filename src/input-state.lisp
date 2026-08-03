(in-package #:cl-tty-kit)

(defparameter +empty-octet-vector+ (make-array 0 :element-type '(unsigned-byte 8)))

(defstruct (input-decoder (:constructor %make-input-decoder) (:copier nil)) "Incremental decoder state for split terminal input."
  (pending-string "")
  (pending-octets +empty-octet-vector+
   :type (vector (unsigned-byte 8)))
  (collect-bracketed-paste-p nil)
  (normalize-paste-line-endings-p nil)
  (pending-paste nil)
  (max-pending 4194304 :type (integer 0 *)))

(defparameter +bracketed-paste-start-sequence+ (concatenate 'string (string #\Esc) "[200~"))

(defparameter +bracketed-paste-end-sequence+ (concatenate 'string (string #\Esc) "[201~"))

(defmacro with-input-decoder-state ((decoder) &body body)
  `(with-accessors ((pending-string input-decoder-pending-string)
      (pending-octets input-decoder-pending-octets)
      (collect-bracketed-paste-p input-decoder-collect-bracketed-paste-p)
      (pending-paste input-decoder-pending-paste))
    ,decoder
    ,@body))
