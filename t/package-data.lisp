(in-package #:cl-tty-kit/test)

(defparameter +expected-system-metadata+
  '((:description . "A small, low-dependency Common Lisp terminal toolkit.")
    (:author . "takeokunn")
    (:maintainer . "takeokunn")
    (:license . "MIT")
    (:homepage . "https://github.com/takeokunn/cl-tty-kit")
    (:bug-tracker . "https://github.com/takeokunn/cl-tty-kit/issues")
    (:source-control . "git https://github.com/takeokunn/cl-tty-kit.git")
    (:version . "0.1.0")))

(defparameter +expected-external-symbols+
  '("TTY-KIT-ERROR"
    "UNSUPPORTED-FEATURE"
    "UNSUPPORTED-FEATURE-FEATURE"
    "INVALID-UTF8-SEQUENCE"
    "INVALID-UTF8-SEQUENCE-POSITION"
    "INVALID-UTF8-SEQUENCE-OCTET"
    "INVALID-UTF8-SEQUENCE-REASON"
    "SCREEN-INDEX-OUT-OF-BOUNDS"
    "SCREEN-INDEX-OUT-OF-BOUNDS-SCREEN"
    "SCREEN-INDEX-OUT-OF-BOUNDS-X"
    "SCREEN-INDEX-OUT-OF-BOUNDS-Y"
    "SCREEN-INDEX-OUT-OF-BOUNDS-WIDTH"
    "SCREEN-INDEX-OUT-OF-BOUNDS-HEIGHT"
    "SCREEN-DIMENSIONS-INVALID"
    "SCREEN-DIMENSIONS-INVALID-WIDTH"
    "SCREEN-DIMENSIONS-INVALID-HEIGHT"
    "CURSOR-PARAMETER-INVALID"
    "CURSOR-PARAMETER-INVALID-PARAMETER"
    "CURSOR-PARAMETER-INVALID-VALUE"
    "CURSOR-PARAMETER-INVALID-EXPECTED"
    "UNSUPPORTED-CODE-POINT"
    "UNSUPPORTED-CODE-POINT-CODE-POINT"
    "RAW-MODE-OPERATION-FAILED"
    "RAW-MODE-OPERATION-FAILED-OPERATION"
    "RAW-MODE-OPERATION-FAILED-FD"
    "RAW-MODE-OPERATION-FAILED-REASON"
    "PTY-OPERATION-FAILED"
    "PTY-OPERATION-FAILED-OPERATION"
    "PTY-OPERATION-FAILED-PTY"
    "PTY-OPERATION-FAILED-REASON"
    "ENABLE-RAW-MODE"
    "DISABLE-RAW-MODE"
    "WITH-RAW-MODE"
    "WITH-TERMINAL-SESSION"
    "ANSI-MOVE-CURSOR"
    "ANSI-CLEAR-SCREEN"
    "ANSI-CLEAR-LINE"
    "ANSI-HIDE-CURSOR"
    "ANSI-SHOW-CURSOR"
    "ANSI-ENTER-ALTERNATE-SCREEN"
    "ANSI-EXIT-ALTERNATE-SCREEN"
    "ANSI-ENABLE-BRACKETED-PASTE"
    "ANSI-DISABLE-BRACKETED-PASTE"
    "ANSI-SET-KEYBOARD-ENHANCEMENTS"
    "ANSI-PUSH-KEYBOARD-ENHANCEMENTS"
    "ANSI-POP-KEYBOARD-ENHANCEMENTS"
    "ANSI-BOLD"
    "ANSI-RESET-STYLE"
    "KEY-EVENT"
    "MAKE-KEY-EVENT"
    "KEY-EVENT-TYPE"
    "KEY-EVENT-CODE"
    "KEY-EVENT-MODIFIERS"
    "INPUT-DECODER"
    "MAKE-INPUT-DECODER"
    "DECODE-INPUT"
    "DECODE-INPUT-CHUNK"
    "DECODE-KEY-SEQUENCE"
    "FLUSH-INPUT-DECODER"
    "CELL"
    "MAKE-CELL"
    "CELL-CHAR"
    "CELL-STYLE"
    "MAKE-STYLE"
    "STYLE-FG"
    "STYLE-BG"
    "COPY-CELL"
    "SCREEN"
    "MAKE-SCREEN"
    "SCREEN-WIDTH"
    "SCREEN-HEIGHT"
    "SCREEN-CELLS"
    "SCREEN-CELL"
    "SCREEN-RESIZE"
    "SCREEN-CLEAR"
    "SCREEN-PUT-CELL"
    "SCREEN-FILL-RECT"
    "SCREEN-WRITE-STRING"
    "CURSOR"
    "MAKE-CURSOR"
    "CURSOR-X"
    "CURSOR-Y"
    "CURSOR-VISIBLE-P"
    "MOVE-CURSOR"
    "RENDER-SCREEN"
    "RENDER-CURSOR"
    "RENDER-DIFF"
    "RENDER-FRAME"
    "RENDER-FRAME-DIFF"
    "PTY"
    "MAKE-PTY"
    "PTY-PROCESS"
    "PTY-STREAM"
    "PTY-READ"
    "PTY-WRITE"
    "CLOSE-PTY"))

(defparameter +expected-readme-commands+
  '("sbcl --script scripts/test.lisp"
    "sbcl --script scripts/examples.lisp"
    "sbcl --script scripts/source-registry-smoke.lisp"
    "sbcl --script scripts/coverage.lisp"
    "sbcl --script scripts/verify.lisp"))

(defparameter +expected-quick-start-fragments+
  '("(make-screen 20 4)"
    "(screen-write-string screen 0 0 \"Hi\")"
    "(format t \"~A~%\" (render-screen screen))"))

(defparameter +expected-streaming-readme-fragments+
  '("(decode-input-chunk decoder (string #\\Esc))"
    "(decode-input-chunk decoder \"[A\")"))

(defparameter +expected-paste-readme-fragments+
  '("(make-input-decoder :collect-bracketed-paste t)"
    "(decode-input-chunk decoder \"hello\")"))
