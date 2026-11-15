(in-package #:cl-tty-kit/test)

(defun %octets (string)
  (sb-ext:string-to-octets string :external-format :utf-8))

(defun %every-proper-prefix-declined-p (decoder report)
  "True when DECODER reports 0 consumed for every proper prefix of REPORT."
  (loop for length from 0 below (length report)
        always (zerop (car (last (multiple-value-list
                                  (funcall decoder (subseq report 0 length))))))))

(describe "terminal capability requests"
  (it "emits XTVERSION, DECRQM, and the kitty flags query"
    (expect (ansi-request-terminal-version) :to-equal (%esc "[>0q"))
    (expect (ansi-request-mode 2026) :to-equal (%esc "[?2026$p"))
    (expect (ansi-request-mode 4 :private nil) :to-equal (%esc "[4$p"))
    (expect (ansi-request-mode 0) :to-equal (%esc "[?0$p"))
    (expect (ansi-request-keyboard-enhancements) :to-equal (%esc "[?u")))
  (it "rejects a DECRQM mode that is not a non-negative integer"
    (expect-non-type-error (ansi-request-mode -1))
    (expect-non-type-error (ansi-request-mode "25"))
    (expect-non-type-error (ansi-request-mode nil))))

(describe "decode-terminal-version"
  (let ((report (%esc "P>|kitty(0.36.4)" (string #\Esc) "\\")))
    (it "decodes an ST-terminated XTVERSION reply"
      (multiple-value-bind (text consumed) (decode-terminal-version report)
        (expect text :to-equal "kitty(0.36.4)")
        (expect consumed :to-be (length report))))
    (it "accepts an empty version text"
      (multiple-value-bind (text consumed)
          (decode-terminal-version (%esc "P>|" (string #\Esc) "\\"))
        (expect text :to-equal "")
        (expect consumed :to-be 6)))
    (it "declines every proper prefix"
      (expect (%every-proper-prefix-declined-p #'decode-terminal-version report)
              :to-be-truthy))
    (it "decodes at a non-zero START and excludes trailing data"
      (multiple-value-bind (text consumed)
          (decode-terminal-version (concatenate 'string "ab" report "tail") :start 2)
        (expect text :to-equal "kitty(0.36.4)")
        (expect consumed :to-be (length report))))
    (it "decodes octet-vector input, counting characters"
      (multiple-value-bind (text consumed)
          (decode-terminal-version (%octets (%esc "P>|t" (string (code-char #xE9))
                                                  (string #\Esc) "\\")))
        (expect text :to-equal (format nil "t~C" (code-char #xE9)))
        (expect consumed :to-be 8)))
    (it "rejects a BEL terminator, embedded controls, and other DCS replies"
      (dolist (input (list (%esc "P>|xterm" (string (code-char 7)))
                           (%esc "P>|x" (string (code-char 7)) "y" (string #\Esc) "\\")
                           (%esc "P>|x" (string #\Esc) "]" (string #\Esc) "\\")
                           (%esc "P1$r0m" (string #\Esc) "\\")
                           (%esc "[>0q")
                           "P>|x"))
        (multiple-value-bind (text consumed) (decode-terminal-version input)
          (expect text :to-be-falsy)
          (expect consumed :to-be 0))))
    (it "declines an out-of-range or non-integer START"
      (dolist (start (list -1 1.5 (length report) (1+ (length report)) nil))
        (expect (nth-value 1 (decode-terminal-version report :start start)) :to-be 0)))))

(describe "decode-mode-report"
  (it "decodes every DECRPM state for a private mode"
    (loop for ps from 0
          for state in '(:not-recognized :set :reset :permanently-set :permanently-reset)
          do (let ((report (%esc (format nil "[?2026;~D$y" ps))))
               (multiple-value-bind (mode decoded private-p consumed)
                   (decode-mode-report report)
                 (expect mode :to-be 2026)
                 (expect decoded :to-be state)
                 (expect private-p :to-be t)
                 (expect consumed :to-be (length report))))))
  (it "decodes an ANSI (non-private) mode report"
    (multiple-value-bind (mode state private-p consumed) (decode-mode-report (%esc "[4;2$y"))
      (expect mode :to-be 4)
      (expect state :to-be :reset)
      (expect private-p :to-be-falsy)
      (expect consumed :to-be 7)))
  (it "declines every proper prefix of private and ANSI reports"
    (expect (%every-proper-prefix-declined-p #'decode-mode-report (%esc "[?25;1$y"))
            :to-be-truthy)
    (expect (%every-proper-prefix-declined-p #'decode-mode-report (%esc "[20;2$y"))
            :to-be-truthy))
  (it "decodes at a non-zero START from octets and excludes trailing data"
    (multiple-value-bind (mode state private-p consumed)
        (decode-mode-report (%octets (concatenate 'string "xy" (%esc "[?1049;1$y") "z"))
                            :start 2)
      (expect mode :to-be 1049)
      (expect state :to-be :set)
      (expect private-p :to-be t)
      (expect consumed :to-be 11)))
  (it "declines unknown states, malformed fields, and oversize numbers"
    (dolist (input (list (%esc "[?25;5$y")
                         (%esc "[?25;12$y")
                         (%esc "[?;1$y")
                         (%esc "[?25;$y")
                         (%esc "[?25$y")
                         (%esc "[?25;1y")
                         (%esc "[?25;1$p")
                         (%esc "[?2a;1$y")
                         (%esc "[?25;1;1$y")
                         (%esc "[>25;1$y")
                         (%esc "[?" (make-string 40 :initial-element #\9) ";1$y")
                         (%esc "[?1;" (make-string 40 :initial-element #\1) "$y")))
      (multiple-value-bind (mode state private-p consumed) (decode-mode-report input)
        (expect mode :to-be-falsy)
        (expect state :to-be-falsy)
        (expect private-p :to-be-falsy)
        (expect consumed :to-be 0))))
  (it "declines an out-of-range START"
    (expect (nth-value 3 (decode-mode-report (%esc "[?25;1$y") :start -1)) :to-be 0)
    (expect (nth-value 3 (decode-mode-report (%esc "[?25;1$y") :start 99)) :to-be 0)))

(describe "decode-keyboard-enhancements-report"
  (it "decodes the flags reply"
    (multiple-value-bind (flags consumed) (decode-keyboard-enhancements-report (%esc "[?31u"))
      (expect flags :to-be 31)
      (expect consumed :to-be 6))
    (expect (decode-keyboard-enhancements-report (%esc "[?0u")) :to-be 0))
  (it "declines every proper prefix"
    (expect (%every-proper-prefix-declined-p #'decode-keyboard-enhancements-report
                                             (%esc "[?15u"))
            :to-be-truthy))
  (it "decodes at a non-zero START from octets and excludes trailing data"
    (multiple-value-bind (flags consumed)
        (decode-keyboard-enhancements-report (%octets (concatenate 'string "a" (%esc "[?1u")
                                                                   (%esc "[A")))
                                             :start 1)
      (expect flags :to-be 1)
      (expect consumed :to-be 5)))
  (it "declines malformed and oversize reports"
    (dolist (input (list (%esc "[?u")
                         (%esc "[1u")
                         (%esc "[?1;2u")
                         (%esc "[?1x")
                         (%esc "[=1u")
                         (%esc "[?" (make-string 40 :initial-element #\7) "u")))
      (multiple-value-bind (flags consumed) (decode-keyboard-enhancements-report input)
        (expect flags :to-be-falsy)
        (expect consumed :to-be 0))))
  (it "declines an out-of-range START"
    (expect (nth-value 1 (decode-keyboard-enhancements-report (%esc "[?1u") :start 4))
            :to-be 0)))
