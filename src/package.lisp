(defpackage #:cl-tty-kit/prolog
  (:use #:cl)
  (:nicknames #:tty-prolog)
  (:documentation
   "A small embedded logic engine: unification plus CPS resolution over an
explicit clause database. cl-tty-kit expresses its pure decision logic as
relations resolved by this engine.")
  (:export
   #:clause-db
   #:add-clause
   #:add-primitive
   #:define-primitive
   #:variable-p
   #:unify
   #:subst-bindings
   #:+no-bindings+
   #:+fail+
   #:solutions
   #:provable-p
   #:install-standard-primitives))

(defpackage #:cl-tty-kit
  (:use #:cl)
  (:export
   ;; conditions
   #:tty-kit-error
   #:unsupported-feature
   #:unsupported-feature-feature
   #:invalid-utf8-sequence
   #:invalid-utf8-sequence-position
   #:invalid-utf8-sequence-octet
   #:invalid-utf8-sequence-reason
   #:screen-index-out-of-bounds
   #:screen-index-out-of-bounds-screen
   #:screen-index-out-of-bounds-x
   #:screen-index-out-of-bounds-y
   #:screen-index-out-of-bounds-width
   #:screen-index-out-of-bounds-height
   #:screen-dimensions-invalid
   #:screen-dimensions-invalid-width
   #:screen-dimensions-invalid-height
   #:cursor-parameter-invalid
   #:cursor-parameter-invalid-parameter
   #:cursor-parameter-invalid-value
   #:cursor-parameter-invalid-expected
   #:unsupported-code-point
   #:unsupported-code-point-code-point
   #:raw-mode-operation-failed
   #:raw-mode-operation-failed-operation
   #:raw-mode-operation-failed-fd
   #:raw-mode-operation-failed-reason
   #:pty-operation-failed
   #:pty-operation-failed-operation
   #:pty-operation-failed-pty
   #:pty-operation-failed-reason
   ;; raw mode
   #:enable-raw-mode
   #:disable-raw-mode
   #:with-raw-mode
   ;; terminal session
   #:with-terminal-session-output
   #:with-terminal-session
   ;; ansi
   #:ansi-move-cursor
   #:ansi-clear-screen
   #:ansi-clear-line
   #:ansi-hide-cursor
   #:ansi-show-cursor
   #:ansi-enter-alternate-screen
   #:ansi-exit-alternate-screen
   #:ansi-enable-bracketed-paste
   #:ansi-disable-bracketed-paste
   #:ansi-set-keyboard-enhancements
   #:ansi-push-keyboard-enhancements
   #:ansi-pop-keyboard-enhancements
   #:ansi-bold
   #:ansi-reset-style
   ;; keys and input
   #:key-event
   #:make-key-event
   #:key-event-type
   #:key-event-code
   #:key-event-modifiers
   #:input-decoder
   #:make-input-decoder
   #:decode-input-chunk
   #:flush-input-decoder
   #:decode-key-sequence
   ;; character width
   #:char-width
   ;; screen and cells
   #:cell
   #:make-cell
   #:cell-char
   #:cell-style
   #:make-style
   #:style-fg
   #:style-bg
   #:copy-cell
   #:screen
   #:make-screen
   #:screen-width
   #:screen-height
   #:screen-cells
   #:screen-cell
   #:screen-put-cell
   #:screen-write-string
   ;; cursor
   #:cursor
   #:make-cursor
   #:cursor-x
   #:cursor-y
   #:cursor-visible-p
   ;; render
   #:render-screen
   #:render-cursor
   #:render-diff
   #:render-frame
   #:render-frame-diff
   ;; pty
   #:pty
   #:make-pty
   #:pty-process
   #:pty-stream
   #:pty-read
   #:pty-write
   #:close-pty))
