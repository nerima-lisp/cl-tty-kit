(in-package #:cl-tty-kit/test)

(defun %osc-st-frame (body)
  (%esc "]" body (string #\Esc) "\\"))

(describe "OSC 133 semantic prompt marks"
  (it "emits the A/B/C marks with an ST terminator"
    (expect (ansi-prompt-start) :to-equal (%osc-st-frame "133;A"))
    (expect (ansi-command-start) :to-equal (%osc-st-frame "133;B"))
    (expect (ansi-command-output-start) :to-equal (%osc-st-frame "133;C")))
  (it "emits D with and without an exit status"
    (expect (ansi-command-finished) :to-equal (%osc-st-frame "133;D"))
    (expect (ansi-command-finished 0) :to-equal (%osc-st-frame "133;D;0"))
    (expect (ansi-command-finished 127) :to-equal (%osc-st-frame "133;D;127")))
  (it "rejects an exit status that is not a non-negative integer"
    (expect-non-type-error (ansi-command-finished -1))
    (expect-non-type-error (ansi-command-finished 1.5))
    (expect-non-type-error (ansi-command-finished "0"))))

(describe "ansi-set-working-directory (OSC 7)"
  (it "frames a plain path with the given host"
    (expect (ansi-set-working-directory "/home/user/src" :host "box")
            :to-equal (%osc-st-frame "7;file://box/home/user/src")))
  (it "defaults HOST to MACHINE-INSTANCE"
    (expect (ansi-set-working-directory "/tmp" :host (machine-instance))
            :to-equal (ansi-set-working-directory "/tmp")))
  (it "yields an empty authority for a NIL host"
    (expect (ansi-set-working-directory "/" :host nil)
            :to-equal (%osc-st-frame "7;file:///")))
  (it "percent-encodes reserved, space, control, and non-ASCII octets in uppercase hex"
    (expect (ansi-set-working-directory
             (format nil "/a b/%;?#~C/~C/x-._~~" (code-char #xE9) (code-char 7))
             :host "h")
            :to-equal (%osc-st-frame "7;file://h/a%20b/%25%3B%3F%23%C3%A9/%07/x-._~")))
  (it "encodes a multi-byte character as its UTF-8 octets"
    (expect (ansi-set-working-directory (format nil "/~C" (code-char #x65E5)) :host "h")
            :to-equal (%osc-st-frame "7;file://h/%E6%97%A5")))
  (it "strips control characters from HOST and encodes its slashes and colons"
    (expect (ansi-set-working-directory
             "/p" :host (format nil "a~C~C]b/c:d" #\Esc (code-char 7)))
            :to-equal (%osc-st-frame "7;file://a%5Db%2Fc%3Ad/p")))
  (it "rejects a relative, empty, or non-string path"
    (expect-non-type-error (ansi-set-working-directory "relative" :host "h"))
    (expect-non-type-error (ansi-set-working-directory "" :host "h"))
    (expect-non-type-error (ansi-set-working-directory #p"/tmp/" :host "h"))
    (expect-non-type-error (ansi-set-working-directory nil :host "h"))))

(describe "ansi-notify"
  (it "defaults to OSC 777 with an empty title"
    (expect (ansi-notify "done")
            :to-equal (%osc-st-frame "777;notify;;done")))
  (it "strips ; from an OSC 777 title but keeps it in the body"
    (expect (ansi-notify "a;b" :title "T;i;t" :protocol :osc-777)
            :to-equal (%osc-st-frame "777;notify;Tit;a;b")))
  (it "emits OSC 9 with BODY alone or TITLE: BODY"
    (expect (ansi-notify "done" :protocol :osc-9)
            :to-equal (%osc-st-frame "9;done"))
    (expect (ansi-notify "done" :title "Build" :protocol :osc-9)
            :to-equal (%osc-st-frame "9;Build: done")))
  (it "emits a single kitty OSC 99 body chunk without a title"
    (expect (ansi-notify "done" :protocol :osc-99)
            :to-equal (%osc-st-frame "99;p=body;done"))
    (expect (ansi-notify "done" :protocol :osc-99 :id "job-1")
            :to-equal (%osc-st-frame "99;i=job-1:p=body;done")))
  (it "emits a title chunk and a body chunk sharing an id with a title"
    (expect (ansi-notify "done" :title "Build" :protocol :osc-99 :id "a_b+c.d-1")
            :to-equal (concatenate 'string
                                   (%osc-st-frame "99;i=a_b+c.d-1:d=0:p=title;Build")
                                   (%osc-st-frame "99;i=a_b+c.d-1:d=1:p=body;done")))
    (expect (ansi-notify "done" :title "Build" :protocol :osc-99)
            :to-equal (concatenate 'string
                                   (%osc-st-frame "99;i=1:d=0:p=title;Build")
                                   (%osc-st-frame "99;i=1:d=1:p=body;done"))))
  (it "strips control characters from every payload"
    (let ((dirty (format nil "x~C\\~C~Cy" #\Esc (code-char 7) (code-char #x9C))))
      (expect (ansi-notify dirty :title dirty)
              :to-equal (%osc-st-frame "777;notify;x\\y;x\\y"))
      (expect (ansi-notify dirty :title dirty :protocol :osc-9)
              :to-equal (%osc-st-frame "9;x\\y: x\\y"))
      (expect (ansi-notify dirty :protocol :osc-99)
              :to-equal (%osc-st-frame "99;p=body;x\\y"))))
  (it "rejects an OSC 99 id outside [A-Za-z0-9_+.-]+"
    (expect-non-type-error (ansi-notify "x" :protocol :osc-99 :id "a:b"))
    (expect-non-type-error (ansi-notify "x" :protocol :osc-99 :id "a;b"))
    (expect-non-type-error (ansi-notify "x" :protocol :osc-99 :id ""))
    (expect-non-type-error (ansi-notify "x" :title "t" :protocol :osc-99 :id "a b")))
  (it "rejects an unknown protocol"
    (expect-non-type-error (ansi-notify "x" :protocol :osc-42))
    (expect-non-type-error (ansi-notify "x" :protocol nil))))
