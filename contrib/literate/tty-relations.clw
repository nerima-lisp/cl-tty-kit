% Literate contrib for cl-tty-kit, written for clweb --- the Common Lisp
% descendant of Knuth's WEB, i.e. the CL "weave" tool.
%
%   (ql:quickload :clweb)
%   (clweb:tangle-file "contrib/literate/tty-relations.clw")  ; -> tty-relations.lisp
%   (clweb:weave "contrib/literate/tty-relations.clw")        ; -> tty-relations.tex
%
% Tangling extracts the program below; weaving typesets this same source.

@*Clauses to an external ISO Prolog. A clause written as a plain Lisp list of
the shape |(head . body)|, with logic variables as |?|-prefixed symbols, is
cl-prolog-kit's own clause DSL shape (see the Rule DSL docs) and happens to match
the convention the maintained |cl-prolog2| library uses to drive a full
external ISO Prolog. This module captures --- literately --- the one
structural rewrite that lets such a clause cross from the Lisp-list shape to
an ISO Prolog rule term.

@l
(defpackage "CL-TTY-KIT/LITERATE"
  (:use "COMMON-LISP")
  (:documentation "Rewrites Lisp-shaped (HEAD . BODY) clauses into cl-prolog2 ISO rule sexps.")
  (:export "CLAUSE->PROLOG2-RULE" "CLAUSES->PROLOG2-RULES"))
(in-package "CL-TTY-KIT/LITERATE")

@ A clause with no body is a fact, and travels unchanged. A clause with a body
becomes an ISO rule, written |(:- head goal...)|. That is the whole of it.

@l
(defun clause->prolog2-rule (clause)
  "Rewrite a Lisp-shaped clause (HEAD . BODY) as a cl-prolog2 rule sexp."
  (let ((head (first clause))
        (body (rest clause)))
    (if body
        @<Build an ISO rule from |head| and |body|@>
        head)))

@ The rule constructor is small, but naming it keeps the intent legible and
lets the weave point at it.

@<Build an ISO rule...@>=(list* :- head body)

@ Translating a whole program is just a map over its clauses.

@l
(defun clauses->prolog2-rules (clauses)
  "Rewrite a list of Lisp-shaped clauses into cl-prolog2 rule sexps."
  (mapcar #'clause->prolog2-rule clauses))
