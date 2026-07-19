(defpackage #:cl-tty-kit/prolog-bridge
  (:use #:cl)
  (:nicknames #:tty-prolog-bridge)
  (:documentation
   "Advanced usage of cl-prolog2: run cl-tty-kit's embedded clause database on a
full external ISO Prolog. The embedded engine (`cl-tty-kit/prolog`) is a compact
CPS resolver; delegating to swipl/gprolog/yap through cl-prolog2 adds ISO
built-ins (arithmetic, cut, findall, negation, I/O) for the times a terminal app
outgrows the in-image engine. Both sides already spell logic variables as
`?`-prefixed symbols, so clause translation is a direct structural rewrite.")
  (:export #:clause->prolog2-rule
           #:clause-db-rules
           #:run-clause-db-query))

(in-package #:cl-tty-kit/prolog-bridge)

(defun clause->prolog2-rule (clause)
  "Translate one cl-tty-kit clause (HEAD . BODY) into a cl-prolog2 rule sexp.
A body-less clause becomes the bare head fact; otherwise it becomes
`(:- HEAD BODY...)`. Logic variables need no rewriting because cl-prolog2 also
treats `?`-prefixed symbols as variables."
  (let ((head (first clause))
        (body (rest clause)))
    (if body
        (list* :- head body)
        head)))

(defun clause-db-rules (db)
  "Return every clause stored in a cl-tty-kit clause database DB as a list of
cl-prolog2 rule sexps, preserving each relation's definition order. Primitive
relations (installed in Lisp) have no clauses and are skipped."
  (let ((rules '()))
    (maphash
     (lambda (relation entry)
       (declare (ignore relation))
       (dolist (clause (cl-tty-kit/prolog::relation-entry-clauses entry))
         (push (clause->prolog2-rule clause) rules)))
     (cl-tty-kit/prolog::clause-db-relations db))
    (nreverse rules)))

(defun run-clause-db-query (db query template &key (prolog :swi) debug)
  "Run DB plus a QUERY on an external ISO Prolog through cl-prolog2 and print
TEMPLATE once per solution. Returns the interpreter's raw output string.

DB is a `cl-tty-kit/prolog` clause database, QUERY and TEMPLATE are ordinary
cl-tty-kit goal terms (e.g. QUERY `(ancestor abraham ?d)`, TEMPLATE `?d`).
Requires the PROLOG binary (default swipl) on PATH."
  (cl-prolog2:run-prolog
   (append (clause-db-rules db)
           `((:- main
                 (forall ,query (and (writeln ,template) true))
                 halt)
             (:- (initialization main))))
   prolog
   :debug debug))
