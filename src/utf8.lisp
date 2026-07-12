(in-package #:cl-tty-kit)

(declaim (ftype function %signal-invalid-utf8-sequence))

(defparameter +utf8-leading-byte-rules+
  '((#xC2 #xDF 2 #x1F :min-code-point #x80)
    (#xE0 #xEF 3 #x0F :min-code-point #x800)
    (#xF0 #xF4 4 #x07 :min-code-point #x10000)))

(defun %utf8-continuation-octet-p (octet)
  (and (<= #x80 octet)
       (<= octet #xBF)))

(defun %utf8-octet-at (vector index)
  (let ((octet (aref vector index)))
    (unless (typep octet '(integer 0 255))
      (%signal-invalid-utf8-sequence index octet :non-octet))
    octet))

(defun %string-to-utf8-octets (string)
  (sb-ext:string-to-octets string :external-format :utf-8))

(defun %utf8-emit-code-point (code)
  (or (code-char code)
      (error 'unsupported-code-point :code-point code)))

(defun %utf8-leading-byte-rule (octet)
  (find-if (lambda (rule)
             (destructuring-bind (lower upper &rest _rest) rule
               (declare (ignore _rest))
                (<= lower octet upper)))
            +utf8-leading-byte-rules+))

(defun %utf8-read-continuation-octets (vector index count)
  (loop for offset from 1 to count
        for octet-index = (+ index offset)
        for octet = (%utf8-octet-at vector octet-index)
        unless (%utf8-continuation-octet-p octet)
          do (%signal-invalid-utf8-sequence octet-index octet
                                            :invalid-continuation-byte)
        collect octet))

(defun %utf8-assemble-code-point (first payload-mask continuation-octets)
  (reduce (lambda (code octet)
            (+ (ash code 6) (logand octet #x3F)))
          continuation-octets
          :initial-value (logand first payload-mask)))

(defun %utf8-validate-code-point (index first code-point second-octet min-code-point)
  (when (< code-point min-code-point)
    (%signal-invalid-utf8-sequence index first :overlong-sequence))
  (when (<= #xD800 code-point #xDFFF)
    (%signal-invalid-utf8-sequence index first :surrogate-half))
  (when (> code-point #x10FFFF)
    (%signal-invalid-utf8-sequence index first :code-point-too-large))
  (when (and (= first #xF4) (> second-octet #x8F))
    (%signal-invalid-utf8-sequence index first :code-point-too-large)))

(defun %utf8-decode-multibyte (vector index length first rule)
  (destructuring-bind (_lower _upper sequence-length payload-mask
                       &key min-code-point)
      rule
    (declare (ignore _lower _upper))
    (when (> (+ index sequence-length) length)
      (%signal-invalid-utf8-sequence index first :truncated-sequence))
    (let* ((continuation-count (1- sequence-length))
           (continuation-octets
             (%utf8-read-continuation-octets vector index continuation-count))
           (code-point
             (%utf8-assemble-code-point first payload-mask continuation-octets)))
      (%utf8-validate-code-point index
                                 first
                                 code-point
                                 (first continuation-octets)
                                 min-code-point)
      (values (%utf8-emit-code-point code-point)
              (+ index sequence-length)))))

(defun %utf8-decode-at (vector index length)
  (let ((first (%utf8-octet-at vector index)))
    (cond
      ((< first #x80)
       (values (%utf8-emit-code-point first) (1+ index)))
      (t
       (let ((rule (%utf8-leading-byte-rule first)))
         (unless rule
           (%signal-invalid-utf8-sequence index first :invalid-leading-byte))
         (%utf8-decode-multibyte vector index length first rule))))))

(defun %utf8-write-decoded-octets (vector stream)
  (loop with index = 0
        with limit = (length vector)
        while (< index limit)
        do (multiple-value-bind (char next-index)
               (%utf8-decode-at vector index limit)
             (write-char char stream)
             (setf index next-index))))

(defun %utf8-octets-to-string (vector)
  (with-output-to-string (stream)
    (%utf8-write-decoded-octets vector stream)))
