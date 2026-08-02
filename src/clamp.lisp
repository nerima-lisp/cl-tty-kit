(in-package #:cl-tty-kit)

;; CLAMP and %PROPER-LIST-P stay DEFUNs, not DEFMACROs, despite otherwise
;; qualifying (never passed as a value, never recursive): both are
;; contrib/weave-mutation-tests.lisp's flagship examples, cited by name in
;; docs/src/project/quality-gates.md as this project's preferred alternative
;; to chasing sb-cover percentages. That harness's %READ-DEFUN-FORMS reads
;; the live DEFUN body and mutates it directly; a DEFMACRO's body is a
;; backquote template that *generates* code rather than code that computes a
;; value, so re-evaluating a mutated copy of it would exercise the
;; template-expansion machinery, not CLAMP's actual arithmetic -- silently
;; invalidating the mutation-kill claim instead of computing it. Keeping
;; these as DEFUNs keeps that quality signal real.
(defun clamp (value min max)
  (if (> min max)
      min
      (min max (max min value))))

(defmacro ensure-list* (value)
  `(let ((value ,value))
     (if (listp value) value (list value))))

(defun %proper-list-p (value)
  "Return true when VALUE is a proper (non-dotted, finite) list."
  (loop for rest = value then (cdr rest)
        while (consp rest)
        finally (return (null rest))))
