% Literate contrib for cl-tty-kit, written for clweb --- the Common Lisp
% descendant of Knuth's WEB, i.e. the CL "weave" tool.
%
%   (ql:quickload :clweb)
%   (clweb:tangle-file "contrib/literate/tty-relations.clw")  ; -> tty-relations.lisp
%   (clweb:weave "contrib/literate/tty-relations.clw")        ; -> tty-relations.tex
%
% Tangling extracts the program below; weaving typesets this same source.

@*Relations across two engines. cl-tty-kit ships a compact embedded logic
engine whose clauses are plain lists of the shape |(head . body)|, with logic
variables written as |?|-prefixed symbols. The maintained |cl-prolog2| library
drives a full external ISO Prolog and, happily, uses the very same convention
for variables. This module captures --- literately --- the one structural
rewrite that lets a clause cross from the in-image engine to ISO Prolog.

@l
(defpackage "CL-TTY-KIT/LITERATE"
  (:use "COMMON-LISP")
  (:documentation "A clweb-tangled companion to cl-tty-kit-prolog-bridge.")
  (:export "CLAUSE->PROLOG2-RULE" "CLAUSES->PROLOG2-RULES"))
(in-package "CL-TTY-KIT/LITERATE")

@ A clause with no body is a fact, and travels unchanged. A clause with a body
becomes an ISO rule, written |(:- head goal...)|. That is the whole of it.

@l
(defun clause->prolog2-rule (clause)
  "Rewrite a cl-tty-kit clause (HEAD . BODY) as a cl-prolog2 rule sexp."
  (let ((head (first clause))
        (body (rest clause)))
    (if body
        @<Build an ISO rule from |head| and |body|@>
        head)))

@ The rule constructor is trivial, but naming it keeps the intent legible and
lets the weave point at it.

@<Build an ISO rule...@>=(list* :- head body)

@ Translating a whole program is just a map over its clauses.

@l
(defun clauses->prolog2-rules (clauses)
  "Rewrite a list of cl-tty-kit clauses into cl-prolog2 rule sexps."
  (mapcar #'clause->prolog2-rule clauses))
