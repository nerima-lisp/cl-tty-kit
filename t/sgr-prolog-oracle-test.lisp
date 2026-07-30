(in-package #:cl-tty-kit/prolog-tests)

;;; --------------------------------------------------------------------------
;;; SGR channel grammar as a Prolog oracle
;;;
;;; The imperative SGR decoder in src/sgr-parse.lisp classifies the colour
;;; parameters with a hand-written CASE. Here the same grammar is stated
;;; declaratively -- one relational fact per parameter -- and resolved by
;;; nerima-lisp/cl-prolog. Cross-checking the two catches a drift in either
;;; direction: the decoder is the fast path, the relation is the independent
;;; specification. This keeps the data (the grammar) apart from the logic (the
;;; decoder) and exercises CL-PROLOG:QUERY-PROLOG / PROLOG-SUCCEEDS-P as
;;; first-class code.
;;;
;;; (sgr-channel PARAM CHANNEL): PARAM touches CHANNEL. 38/48/58 set an extended
;;; colour on the channel; 39/49/59 reset it.
;;; --------------------------------------------------------------------------

(defun %sgr-channel-grammar ()
  (cl-prolog:prolog
    ((sgr-channel 38 :fg))
    ((sgr-channel 39 :fg))
    ((sgr-channel 48 :bg))
    ((sgr-channel 49 :bg))
    ((sgr-channel 58 :underline-color))
    ((sgr-channel 59 :underline-color))))

(describe "the SGR channel grammar oracle"
  ;; Every reset parameter resolves to a single channel, and the decoder in
  ;; sgr-parse.lisp must return exactly that channel.
  (dolist (reset-case '((39 :fg) (49 :bg) (59 :underline-color)))
    (destructuring-bind (code channel) reset-case
      (it (format nil "the relation resolves sgr-channel ~D to its channel" code)
        (expect (%project-variable (%sgr-channel-grammar)
                                   `(sgr-channel ,code ?channel) '?channel)
                :to-equal (list channel)))
      (it (format nil "the decoder agrees with the relation for reset parameter ~D" code)
        (expect (cl-tty-kit::%sgr-color-reset-channel code) :to-equal channel))))
  ;; QUERY-PROLOG enumerates, in definition order, every parameter driving a
  ;; channel -- the set/reset pair for each.
  (it "enumerates every :fg parameter in definition order"
    (expect (%project-variable (%sgr-channel-grammar) '(sgr-channel ?param :fg) '?param)
            :to-equal '(38 39)))
  (it "enumerates every :bg parameter in definition order"
    (expect (%project-variable (%sgr-channel-grammar) '(sgr-channel ?param :bg) '?param)
            :to-equal '(48 49)))
  (it "enumerates every :underline-color parameter in definition order"
    (expect (%project-variable (%sgr-channel-grammar)
                               '(sgr-channel ?param :underline-color) '?param)
            :to-equal '(58 59)))
  ;; A basic colour parameter is not part of the channel-selection grammar.
  (it "a basic colour parameter is not part of the channel-selection grammar"
    (expect (not (cl-prolog:prolog-succeeds-p (%sgr-channel-grammar) '(sgr-channel 30 :fg))))))
