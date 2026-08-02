(in-package #:cl-tty-kit/test)

(describe
  "screen and cursor visibility escapes"
  (it
    "ansi-clear-screen"
    (expect (ansi-clear-screen) :to-equal (format nil "~C[2J" #\Esc)))
  (it
    "ansi-clear-line"
    (expect (ansi-clear-line) :to-equal (format nil "~C[2K" #\Esc)))
  (it
    "ansi-move-cursor"
    (expect (ansi-move-cursor 3 4) :to-equal (format nil "~C[3;4H" #\Esc)))
  (it
    "ansi-hide-cursor / ansi-show-cursor"
    (expect (ansi-hide-cursor) :to-equal (format nil "~C[?25l" #\Esc))
    (expect (ansi-show-cursor) :to-equal (format nil "~C[?25h" #\Esc))))

(describe
  "low-level stream writers"
  (it
    "%write-ansi-clear-screen writes directly to a stream"
    (expect-render-stream-output
      (stream
        (funcall (symbol-function 'cl-tty-kit::%write-ansi-clear-screen) stream))
      (format nil "~C[2J" #\Esc)))
  (it
    "%write-ansi-clear-line writes directly to a stream"
    (expect-render-stream-output
      (stream (funcall (symbol-function 'cl-tty-kit::%write-ansi-clear-line) stream))
      (format nil "~C[0K" #\Esc)))
  (it
    "%write-ansi-move-cursor writes directly to a stream"
    (expect-render-stream-output
      (stream
        (funcall (symbol-function 'cl-tty-kit::%write-ansi-move-cursor) 3 4 stream))
      (format nil "~C[3;4H" #\Esc)))
  (it
    "%write-ansi-cursor-visibility writes directly to a stream"
    (expect-render-stream-output
      (stream
        (funcall (symbol-function 'cl-tty-kit::%write-ansi-cursor-visibility) t stream))
      (format nil "~C[?25h" #\Esc))
    (expect-render-stream-output
      (stream
        (funcall
          (symbol-function 'cl-tty-kit::%write-ansi-cursor-visibility)
          nil
          stream))
      (format nil "~C[?25l" #\Esc)))
  (it
    "%write-ansi-reset-style writes directly to a stream"
    (expect-render-stream-output
      (stream (funcall (symbol-function 'cl-tty-kit::%write-ansi-reset-style) stream))
      (format nil "~C[0m" #\Esc))))

(describe
  "terminal modes"
  (it
    "ansi-enter-alternate-screen / ansi-exit-alternate-screen"
    (expect (ansi-enter-alternate-screen) :to-equal (format nil "~C[?1049h" #\Esc))
    (expect (ansi-exit-alternate-screen) :to-equal (format nil "~C[?1049l" #\Esc)))
  (it
    "ansi-enable-bracketed-paste / ansi-disable-bracketed-paste"
    (expect (ansi-enable-bracketed-paste) :to-equal (format nil "~C[?2004h" #\Esc))
    (expect (ansi-disable-bracketed-paste) :to-equal (format nil "~C[?2004l" #\Esc)))
  (it
    "ansi-enable-focus-reporting / ansi-disable-focus-reporting"
    (expect (ansi-enable-focus-reporting) :to-equal (format nil "~C[?1004h" #\Esc))
    (expect (ansi-disable-focus-reporting) :to-equal (format nil "~C[?1004l" #\Esc)))
  (it
    "ansi-request-cursor-position / ansi-request-device-attributes"
    (expect (ansi-request-cursor-position) :to-equal (format nil "~C[6n" #\Esc))
    (expect (ansi-request-device-attributes) :to-equal (format nil "~C[c" #\Esc)))
  (it
    "ansi-enable-line-wrap / ansi-disable-line-wrap"
    (expect (ansi-enable-line-wrap) :to-equal (format nil "~C[?7h" #\Esc))
    (expect (ansi-disable-line-wrap) :to-equal (format nil "~C[?7l" #\Esc)))
  (it
    "ansi-begin-synchronized-update / ansi-end-synchronized-update"
    (expect
      (ansi-begin-synchronized-update)
      :to-equal
      (format nil "~C[?2026h" #\Esc))
    (expect (ansi-end-synchronized-update) :to-equal (format nil "~C[?2026l" #\Esc))))

(describe
  "ansi-hyperlink"
  (it
    "wraps text with an OSC 8 hyperlink"
    (expect
      (ansi-hyperlink "http://x" "link")
      :to-equal
      (format nil "~C]8;;http://x~C\\link~C]8;;~C\\" #\Esc #\Esc #\Esc #\Esc)))
  (it
    "does not let an embedded escape in the URL or text terminate the OSC early"
    (expect
      (ansi-hyperlink
        (format nil "http://x~C]0;pwn~C" #\Esc (code-char 7))
        (format nil "safe~C[31m" #\Esc))
      :to-equal
      (format
        nil
        "~C]8;;http://x]0;pwn~C\\safe[31m~C]8;;~C\\"
        #\Esc
        #\Esc
        #\Esc
        #\Esc))))

(describe
  "ansi-bell"
  (it
    "rings once by default"
    (expect (ansi-bell) :to-equal (string (code-char 7))))
  (it
    "repeats N times"
    (expect (ansi-bell 3) :to-equal (make-string 3 :initial-element (code-char 7))))
  (it
    "rejects a negative count"
    (expect
      (lambda ()
        (ansi-bell -1))
      :to-throw))
  (it
    "rejects a fractional count"
    (expect
      (lambda ()
        (ansi-bell 1.5))
      :to-throw)))

(describe
  "miscellaneous single-shot escapes"
  (it
    "ansi-reset-terminal"
    (expect (ansi-reset-terminal) :to-equal (format nil "~Cc" #\Esc)))
  (it
    "ansi-default-foreground / ansi-default-background"
    (expect (ansi-default-foreground) :to-equal (format nil "~C[39m" #\Esc))
    (expect (ansi-default-background) :to-equal (format nil "~C[49m" #\Esc)))
  (it
    "ansi-request-foreground-color / ansi-request-background-color"
    (expect
      (ansi-request-foreground-color)
      :to-equal
      (format nil "~C]10;?~C\\" #\Esc #\Esc))
    (expect
      (ansi-request-background-color)
      :to-equal
      (format nil "~C]11;?~C\\" #\Esc #\Esc)))
  (it
    "ansi-cursor-next-line / ansi-cursor-previous-line"
    (expect (ansi-cursor-next-line) :to-equal (format nil "~C[1E" #\Esc))
    (expect (ansi-cursor-next-line 3) :to-equal (format nil "~C[3E" #\Esc))
    (expect (ansi-cursor-previous-line 2) :to-equal (format nil "~C[2F" #\Esc))))

(describe
  "ansi-set-clipboard"
  (it
    "base64-encodes the payload onto the default clipboard selection"
    (expect
      (ansi-set-clipboard "hi")
      :to-equal
      (format nil "~C]52;c;aGk=~C\\" #\Esc #\Esc)))
  (it
    "encodes an empty payload"
    (expect
      (ansi-set-clipboard "")
      :to-equal
      (format nil "~C]52;c;~C\\" #\Esc #\Esc)))
  (it
    "encodes UTF-8 payloads"
    (expect
      (ansi-set-clipboard "あ")
      :to-equal
      (format nil "~C]52;c;44GC~C\\" #\Esc #\Esc)))
  (it
    "streams a 32 KiB payload identically to the reference encoder"
    (let* ((text (make-string (* 32 1024) :initial-element #\x))
           (octets (sb-ext:string-to-octets text :external-format :utf-8))
           (reference
             (format
               nil
               "~C]52;c;~A~C\\"
               #\Esc
               (cl-tty-kit::%base64-encode-octets octets)
               #\Esc))
           (result (ansi-set-clipboard text)))
      (expect (length result) :to-equal 43701)
      (expect (subseq result 0 7) :to-equal (format nil "~C]52;c;" #\Esc))
      (expect
        (subseq result (- (length result) 2))
        :to-equal
        (format nil "~C\\" #\Esc))
      (expect result :to-equal reference)))
  (it
    "accepts an explicit :target selection"
    (expect
      (ansi-set-clipboard "hi" :target "p")
      :to-equal
      (format nil "~C]52;p;aGk=~C\\" #\Esc #\Esc)))
  (it
    "rejects a :target containing a semicolon"
    (expect
      (lambda ()
        (ansi-set-clipboard "hi" :target "c;BAD"))
      :to-throw))
  (it
    "rejects an empty :target"
    (expect
      (lambda ()
        (ansi-set-clipboard "hi" :target ""))
      :to-throw))
  (it
    "encodes base64 padding boundaries exactly"
    (expect (cl-tty-kit::%base64-encode-octets #()) :to-equal "")
    (expect (cl-tty-kit::%base64-encode-octets #(0)) :to-equal "AA==")
    (expect (cl-tty-kit::%base64-encode-octets #(0 1)) :to-equal "AAE=")
    (expect (cl-tty-kit::%base64-encode-octets #(0 1 2)) :to-equal "AAEC"))
  (it
    "writes valid octet ranges without an intermediate string"
    (expect
      (with-output-to-string (out)
        (cl-tty-kit::%write-base64-octets #(99 0 88) out :start 1 :end 2))
      :to-equal
      "AA==")
    (expect
      (with-output-to-string (out)
        (cl-tty-kit::%write-base64-octets #(99 0 1 88) out :start 1 :end 3))
      :to-equal
      "AAE=")
    (expect
      (with-output-to-string (out)
        (cl-tty-kit::%write-base64-octets #(99 0 1 2 88) out :start 1 :end 4))
      :to-equal
      "AAEC")
    (expect
      (with-output-to-string (out)
        (cl-tty-kit::%write-base64-octets #(99 0 1 2 88) out :start 2 :end 2))
      :to-equal
      ""))
  (it
    "rejects invalid octet ranges"
    (dolist (bounds (quote ((-1 1) (2 1) (0 4) (0.5 1))))
      (expect
        (lambda ()
          (with-output-to-string (out)
            (cl-tty-kit::%write-base64-octets
              #(0 1 2)
              out
              :start (first bounds)
              :end (second bounds))))
        :to-throw))))

(describe
  "ansi-set-palette-color / ansi-reset-palette"
  (it
    "sets a palette entry to an RGB color"
    (expect
      (ansi-set-palette-color 1 255 0 0)
      :to-equal
      (format nil "~C]4;1;rgb:FF/00/00~C\\" #\Esc #\Esc)))
  (it
    "resets the whole palette with no index"
    (expect (ansi-reset-palette) :to-equal (format nil "~C]104~C\\" #\Esc #\Esc)))
  (it
    "resets a single palette index"
    (expect
      (ansi-reset-palette 3)
      :to-equal
      (format nil "~C]104;3~C\\" #\Esc #\Esc)))
  (it
    "rejects a negative palette index"
    (expect
      (lambda ()
        (ansi-set-palette-color -1 0 0 0))
      :to-throw))
  (it
    "rejects an out-of-range color channel"
    (expect
      (lambda ()
        (ansi-set-palette-color 0 256 0 0))
      :to-throw))
  (it
    "rejects an out-of-range reset index"
    (expect
      (lambda ()
        (ansi-reset-palette 256))
      :to-throw)))

(describe
  "ansi-set-keyboard-enhancements and friends"
  (it
    "sets a flag bitmask under the default progressive-enhancement mode"
    (expect
      (ansi-set-keyboard-enhancements 5)
      :to-equal
      (format nil "~C[=5;1u" #\Esc)))
  (it
    "accepts an explicit mode"
    (expect
      (ansi-set-keyboard-enhancements 5 3)
      :to-equal
      (format nil "~C[=5;3u" #\Esc)))
  (it
    "rejects a negative flag bitmask"
    (expect
      (lambda ()
        (ansi-set-keyboard-enhancements -1))
      :to-throw))
  (it
    "ansi-push-keyboard-enhancements / ansi-pop-keyboard-enhancements"
    (expect
      (ansi-push-keyboard-enhancements 5)
      :to-equal
      (format nil "~C[>5u" #\Esc))
    (expect (ansi-pop-keyboard-enhancements) :to-equal (format nil "~C[<1u" #\Esc))
    (expect
      (ansi-pop-keyboard-enhancements 2)
      :to-equal
      (format nil "~C[<2u" #\Esc))))

(describe
  "SGR text attribute escapes"
  (it
    "ansi-bold / ansi-dim / ansi-italic / ansi-underline"
    (expect (ansi-bold) :to-equal (format nil "~C[1m" #\Esc))
    (expect (ansi-dim) :to-equal (format nil "~C[2m" #\Esc))
    (expect (ansi-italic) :to-equal (format nil "~C[3m" #\Esc))
    (expect (ansi-underline) :to-equal (format nil "~C[4m" #\Esc)))
  (it
    "ansi-blink / ansi-reverse / ansi-hidden / ansi-strikethrough"
    (expect (ansi-blink) :to-equal (format nil "~C[5m" #\Esc))
    (expect (ansi-reverse) :to-equal (format nil "~C[7m" #\Esc))
    (expect (ansi-hidden) :to-equal (format nil "~C[8m" #\Esc))
    (expect (ansi-strikethrough) :to-equal (format nil "~C[9m" #\Esc)))
  (it
    "ansi-reset-style"
    (expect (ansi-reset-style) :to-equal (format nil "~C[0m" #\Esc))))

(describe
  "ansi-sgr"
  (it
    "with no parameters resets style"
    (expect (ansi-sgr) :to-equal (format nil "~C[m" #\Esc)))
  (it
    "joins integer parameters with semicolons"
    (expect (ansi-sgr 1 38 5 208) :to-equal (format nil "~C[1;38;5;208m" #\Esc)))
  (it
    "accepts a colon-qualified string parameter"
    (expect (ansi-sgr "4:3") :to-equal (format nil "~C[4:3m" #\Esc)))
  (it
    "rejects a negative parameter"
    (expect
      (lambda ()
        (ansi-sgr -1))
      :to-throw))
  (it
    "rejects a string parameter that would escape the SGR sequence"
    (expect
      (lambda ()
        (ansi-sgr (format nil "0m~C]52;c;pwn" #\Esc)))
      :to-throw))
  (it
    "rejects a string parameter containing a semicolon"
    (expect
      (lambda ()
        (ansi-sgr "1;31"))
      :to-throw)))

(describe
  "cursor movement escapes"
  (it
    "ansi-cursor-up defaults to one row and rejects a negative count"
    (expect (ansi-cursor-up) :to-equal (format nil "~C[1A" #\Esc))
    (expect (ansi-cursor-up 4) :to-equal (format nil "~C[4A" #\Esc))
    (expect
      (lambda ()
        (ansi-cursor-up -1))
      :to-throw))
  (it
    "ansi-cursor-down / ansi-cursor-forward / ansi-cursor-back"
    (expect (ansi-cursor-down 2) :to-equal (format nil "~C[2B" #\Esc))
    (expect (ansi-cursor-forward 3) :to-equal (format nil "~C[3C" #\Esc))
    (expect (ansi-cursor-back 5) :to-equal (format nil "~C[5D" #\Esc)))
  (it
    "ansi-cursor-column / ansi-cursor-row"
    (expect (ansi-cursor-column 12) :to-equal (format nil "~C[12G" #\Esc))
    (expect (ansi-cursor-row 7) :to-equal (format nil "~C[7d" #\Esc)))
  (it
    "ansi-save-cursor / ansi-restore-cursor"
    (expect (ansi-save-cursor) :to-equal (format nil "~C7" #\Esc))
    (expect (ansi-restore-cursor) :to-equal (format nil "~C8" #\Esc))))

(describe
  "line and character editing escapes"
  (it
    "ansi-insert-line / ansi-delete-line"
    (expect (ansi-insert-line) :to-equal (format nil "~C[1L" #\Esc))
    (expect (ansi-insert-line 2) :to-equal (format nil "~C[2L" #\Esc))
    (expect (ansi-delete-line 3) :to-equal (format nil "~C[3M" #\Esc)))
  (it
    "ansi-insert-char / ansi-delete-char / ansi-erase-char"
    (expect (ansi-insert-char 4) :to-equal (format nil "~C[4@" #\Esc))
    (expect (ansi-delete-char) :to-equal (format nil "~C[1P" #\Esc))
    (expect (ansi-erase-char 5) :to-equal (format nil "~C[5X" #\Esc)))
  (it "ansi-repeat" (expect (ansi-repeat 3) :to-equal (format nil "~C[3b" #\Esc))))

(describe
  "scrolling escapes"
  (it
    "ansi-scroll-up / ansi-scroll-down"
    (expect (ansi-scroll-up 2) :to-equal (format nil "~C[2S" #\Esc))
    (expect (ansi-scroll-down) :to-equal (format nil "~C[1T" #\Esc)))
  (it
    "ansi-set-scroll-region / ansi-reset-scroll-region"
    (expect (ansi-set-scroll-region 2 10) :to-equal (format nil "~C[2;10r" #\Esc))
    (expect (ansi-reset-scroll-region) :to-equal (format nil "~C[r" #\Esc))))

(describe
  "ansi-set-mode / ansi-reset-mode"
  (it
    "wraps a DEC private mode by default"
    (expect (ansi-set-mode 25) :to-equal (format nil "~C[?25h" #\Esc))
    (expect (ansi-reset-mode 25) :to-equal (format nil "~C[?25l" #\Esc)))
  (it
    ":private nil selects the ANSI (non-DEC) form"
    (expect (ansi-set-mode 4 :private nil) :to-equal (format nil "~C[4h" #\Esc))
    (expect (ansi-reset-mode 4 :private nil) :to-equal (format nil "~C[4l" #\Esc)))
  (it
    "rejects a negative mode"
    (expect
      (lambda ()
        (ansi-set-mode -1))
      :to-throw))
  (it
    "rejects a fractional mode"
    (expect
      (lambda ()
        (ansi-reset-mode 1.5))
      :to-throw))
  (it
    "reproduces the specific private-mode wrappers"
    (expect (ansi-set-mode 2004) :to-equal (ansi-enable-bracketed-paste))
    (expect (ansi-reset-mode 2004) :to-equal (ansi-disable-bracketed-paste))
    (expect (ansi-reset-mode 25) :to-equal (ansi-hide-cursor))))

(describe
  "ansi-set-window-title"
  (it
    "wraps the title in an OSC 0 sequence"
    (expect
      (ansi-set-window-title "hi")
      :to-equal
      (format nil "~C]0;hi~C" #\Esc (code-char 7))))
  (it
    "does not let an embedded OSC terminator in the title escape early"
    (expect
      (ansi-set-window-title (format nil "safe~C]0;pwn~C" #\Esc (code-char 7)))
      :to-equal
      (format nil "~C]0;safe]0;pwn~C" #\Esc (code-char 7)))))

(describe
  "ansi-set-cursor-style"
  (it
    "selects a named style"
    (expect
      (ansi-set-cursor-style :steady-bar)
      :to-equal
      (format nil "~C[6 q" #\Esc))
    (expect (ansi-set-cursor-style :default) :to-equal (format nil "~C[0 q" #\Esc)))
  (it
    "rejects an unknown style"
    (expect
      (lambda ()
        (ansi-set-cursor-style :nope))
      :to-throw)))

(describe
  "ansi-enable-mouse / ansi-disable-mouse"
  (it
    "defaults to button-event tracking with SGR encoding"
    (expect
      (ansi-enable-mouse)
      :to-equal
      (format nil "~C[?1002h~C[?1006h" #\Esc #\Esc)))
  (it
    "accepts :any for any-motion tracking"
    (expect
      (ansi-enable-mouse :any)
      :to-equal
      (format nil "~C[?1003h~C[?1006h" #\Esc #\Esc)))
  (it
    "disables in the reverse order it enables"
    (expect
      (ansi-disable-mouse)
      :to-equal
      (format nil "~C[?1006l~C[?1002l" #\Esc #\Esc)))
  (it
    "rejects an unknown tracking mode"
    (expect
      (lambda ()
        (ansi-enable-mouse :nope))
      :to-throw)))
