(in-package #:cl-tty-kit)

(declaim (notinline sb-unicode:general-category))

(defun %zero-width-general-category-p (category code)
  (or (eq category :mn)
      (eq category :me)
      (and (eq category :cf)
           (/= code #x00AD))))

(defun %unicode-general-category (char)
  (sb-unicode:general-category char))

(defun %code-point-in-ranges-p (code ranges)
  (loop for (start . end) in ranges
        thereis (<= start code end)))

(defun %zero-width-code-point-p (code)
  (let ((char (code-char code)))
    (and char
         (let ((category (%unicode-general-category char)))
           (or (%zero-width-general-category-p category code)
               (<= #x1160 code #x11FF))))))

(defun %wide-code-point-p (code)
  "Return true when CODE occupies two terminal columns."
  (%code-point-in-ranges-p code +wide-code-point-ranges+))

(defun %control-code-point-p (code)
  (and (integerp code)
       (or (< code #x20)
           (<= #x7F code #x9F))))

(defun %code-point-width (code)
  (cond
    ((%control-code-point-p code) 0)
    ((%zero-width-code-point-p code) 0)
    ((%wide-code-point-p code) 2)
    (t 1)))

(defun char-width (character)
  "Return the terminal column width of CHARACTER or a Unicode code point."
  (%code-point-width
   (if (characterp character)
       (char-code character)
       character)))

