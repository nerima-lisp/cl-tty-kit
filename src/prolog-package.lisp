;; The embedded logic engine's package lives in its own file, separate from
;; the main CL-TTY-KIT package: it is a genuinely distinct subsystem (its own
;; nickname, documentation, and export surface) that the CPS proof search in
;; prolog-engine.lisp and friends load against, not part of the terminal
;; toolkit's own public API.

(defpackage #:cl-tty-kit/prolog
  (:use #:cl)
  (:nicknames #:tty-prolog)
  (:documentation
   "A small embedded logic engine: unification plus CPS resolution over an
explicit clause database. cl-tty-kit expresses its pure decision logic as
relations resolved by this engine.")
  (:export
   #:clause-db
   #:make-clause-db
   #:add-clause
   #:define-clauses
   #:add-primitive
   #:define-primitive
   #:variable-p
   #:unify
   #:subst-bindings
   #:+no-bindings+
   #:+fail+
   #:solutions
   #:provable-p
   #:install-standard-primitives
   ;; advanced standard relations installed by INSTALL-STANDARD-PRIMITIVES
   #:true
   #:fail
   #:call
   #:findall))
