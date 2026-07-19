(in-package #:cl-tty-kit)

(defun copy-string-to-output (string stream)
  "Write STRING to STREAM and return STRING.
A small helper for output builders that thread a string through a stream while
still yielding the string they emitted."
  (write-string string stream)
  string)
