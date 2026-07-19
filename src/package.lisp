;; cl-tty-kit currently targets SBCL only: the character-width classification
;; uses SB-UNICODE, UTF-8 transcoding uses SB-EXT, and the raw-mode/PTY layers
;; use SB-POSIX/SB-EXT. Fail fast with a clear message on other implementations
;; rather than letting a later file error out on an unknown package. This file
;; loads before any SBCL-only source, so aborting here stops the build cleanly.
#-sbcl
(error "cl-tty-kit currently requires SBCL (it relies on sb-posix, sb-unicode, ~
and sb-ext). See the \"Compatibility\" section of the README for details.")

(defpackage #:cl-tty-kit/prolog
  (:use #:cl)
  (:nicknames #:tty-prolog)
  (:documentation
   "A small embedded logic engine: unification plus CPS resolution over an
explicit clause database. cl-tty-kit expresses its pure decision logic as
relations resolved by this engine.")
  (:export
   #:clause-db
   #:make-clause-db
   #:add-clause
   #:define-clauses
   #:add-primitive
   #:define-primitive
   #:variable-p
   #:unify
   #:subst-bindings
   #:+no-bindings+
   #:+fail+
   #:solutions
   #:provable-p
   #:install-standard-primitives
   ;; advanced standard relations installed by INSTALL-STANDARD-PRIMITIVES
   #:true
   #:fail
   #:call
   #:findall))

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
   #:decode-input
   #:decode-input-chunk
   #:flush-input-decoder
   #:decode-key-sequence
   ;; character width
   #:char-width
   #:string-width
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
   #:screen-resize
   #:screen-clear
   #:screen-put-cell
   #:screen-fill-rect
   #:screen-write-string
   ;; cursor
   #:cursor
   #:make-cursor
   #:cursor-x
   #:cursor-y
   #:cursor-visible-p
   #:move-cursor
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
