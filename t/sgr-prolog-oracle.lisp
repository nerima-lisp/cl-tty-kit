(in-package #:cl-tty-kit/test)

;;; --------------------------------------------------------------------------
;;; SGR channel grammar as a Prolog oracle
;;;
;;; The imperative SGR decoder in src/sgr-parse.lisp classifies the colour
;;; parameters with a hand-written CASE. Here the same grammar is stated
;;; declaratively -- one relational fact per parameter -- and resolved by the
;;; embedded CPS Prolog engine. Cross-checking the two catches a drift in either
;;; direction: the decoder is the fast path, the relation is the independent
;;; specification. This keeps the data (the grammar) apart from the logic (the
;;; decoder) and exercises TTY-PROLOG:SOLUTIONS / PROVABLE-P as first-class code.
;;;
;;; (sgr-channel PARAM CHANNEL): PARAM touches CHANNEL. 38/48/58 set an extended
;;; colour on the channel; 39/49/59 reset it.
;;; --------------------------------------------------------------------------

(defun %sgr-channel-grammar ()
  (let ((database (tty-prolog:make-clause-db)))
    (tty-prolog:define-clauses database
      ((sgr-channel 38 :fg))
      ((sgr-channel 39 :fg))
      ((sgr-channel 48 :bg))
      ((sgr-channel 49 :bg))
      ((sgr-channel 58 :underline-color))
      ((sgr-channel 59 :underline-color)))
    database))

(defun test-sgr-prolog-oracle ()
  (let ((database (%sgr-channel-grammar)))
    ;; Every reset parameter resolves to a single channel, and the decoder in
    ;; sgr-parse.lisp must return exactly that channel.
    (do-test-case-bind (reset-case '((39 :fg) (49 :bg) (59 :underline-color))
                                   (code channel))
      (is-equal (list channel)
                (tty-prolog:solutions database `(sgr-channel ,code ?channel) '?channel)
                (format nil "relation resolves sgr-channel ~D" code))
      (is-equal channel
                (cl-tty-kit::%sgr-color-reset-channel code)
                (format nil "decoder agrees for reset parameter ~D" code)))
    ;; SOLUTIONS enumerates, in definition order, every parameter driving a
    ;; channel -- the set/reset pair for each.
    (is-equal '(38 39)
              (tty-prolog:solutions database '(sgr-channel ?param :fg) '?param))
    (is-equal '(48 49)
              (tty-prolog:solutions database '(sgr-channel ?param :bg) '?param))
    (is-equal '(58 59)
              (tty-prolog:solutions database
                                    '(sgr-channel ?param :underline-color)
                                    '?param))
    ;; A basic colour parameter is not part of the channel-selection grammar.
    (is (not (tty-prolog:provable-p database '(sgr-channel 30 :fg))))
    t))
