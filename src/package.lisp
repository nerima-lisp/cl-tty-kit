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
   #:terminal-size
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
   #:ansi-hyperlink
   #:ansi-set-clipboard
   #:ansi-set-palette-color
   #:ansi-reset-palette
   #:ansi-request-foreground-color
   #:ansi-request-background-color
   #:ansi-enable-line-wrap
   #:ansi-disable-line-wrap
   #:ansi-cursor-next-line
   #:ansi-cursor-previous-line
   #:ansi-enable-focus-reporting
   #:ansi-disable-focus-reporting
   #:ansi-request-cursor-position
   #:ansi-request-device-attributes
   #:ansi-set-keyboard-enhancements
   #:ansi-push-keyboard-enhancements
   #:ansi-pop-keyboard-enhancements
   #:ansi-bell
   #:ansi-reset-terminal
   #:ansi-begin-synchronized-update
   #:ansi-end-synchronized-update
   #:ansi-default-foreground
   #:ansi-default-background
   #:ansi-bold
   #:ansi-dim
   #:ansi-italic
   #:ansi-underline
   #:ansi-blink
   #:ansi-reverse
   #:ansi-hidden
   #:ansi-strikethrough
   #:ansi-reset-style
   #:ansi-sgr
   #:ansi-cursor-up
   #:ansi-cursor-down
   #:ansi-cursor-forward
   #:ansi-cursor-back
   #:ansi-cursor-column
   #:ansi-cursor-row
   #:ansi-save-cursor
   #:ansi-restore-cursor
   #:ansi-insert-line
   #:ansi-delete-line
   #:ansi-insert-char
   #:ansi-delete-char
   #:ansi-erase-char
   #:ansi-repeat
   #:ansi-scroll-up
   #:ansi-scroll-down
   #:ansi-set-scroll-region
   #:ansi-reset-scroll-region
   #:ansi-set-mode
   #:ansi-reset-mode
   #:ansi-set-window-title
   #:ansi-set-cursor-style
   #:ansi-enable-mouse
   #:ansi-disable-mouse
   ;; keys and input
   #:key-event
   #:make-key-event
   #:key-event-type
   #:key-event-code
   #:key-event-modifiers
   #:key-event-kind
   #:key-event-text
   #:key-event-shifted-key
   #:key-event-base-key
   #:input-decoder
   #:make-input-decoder
   #:decode-input
   #:decode-input-chunk
   #:flush-input-decoder
   #:decode-key-sequence
   #:decode-cursor-position-report
   #:decode-color-report
   #:decode-device-attributes
   #:decode-sgr
   #:parse-styled-string
   #:key-event->string
   ;; mouse input
   #:mouse-event
   #:make-mouse-event
   #:mouse-event-button
   #:mouse-event-action
   #:mouse-event-x
   #:mouse-event-y
   #:mouse-event-modifiers
   #:decode-mouse-sequence
   ;; character width
   #:char-width
   #:string-width
   #:string-graphemes
   #:grapheme-count
   #:grapheme-width
   ;; text layout
   #:truncate-string
   #:pad-string
   #:wrap-string
   #:expand-tabs
   #:chop-string
   #:strip-ansi
   #:*east-asian-ambiguous-wide*
   ;; color utilities
   #:parse-hex-color
   #:parse-color
   #:color-256-to-rgb
   #:rgb-to-256
   #:rgb-to-ansi16
   #:color-luminance
   #:contrast-color
   #:rgb-to-hsl
   #:hsl-to-rgb
   #:rgb-to-hsv
   #:hsv-to-rgb
   #:blend-colors
   #:color-gradient
   ;; formatting widgets
   #:format-progress-bar
   #:format-columns
   #:format-table
   #:format-sparkline
   #:spinner-frame
   #:format-sixel
   #:ansi-kitty-image
   ;; rectangles and layout
   #:rect
   #:make-rect
   #:rect-x
   #:rect-y
   #:rect-width
   #:rect-height
   #:rect-inset
   #:rect-split-horizontal
   #:rect-split-vertical
   #:rect-contains-p
   #:rect-empty-p
   #:rect-area
   #:rect-intersect
   #:rect-union
   #:layout-split
   ;; screen and cells
   #:cell
   #:make-cell
   #:cell-char
   #:cell-style
   #:make-style
   #:style-fg
   #:style-bg
   #:style-underline-color
   #:style-ansi
   #:style-merge
   #:named-color
   #:copy-cell
   #:cell-blank-p
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
   #:screen-fill
   #:screen-write-string
   #:screen-copy
   #:screen-row-string
   #:screen-scroll
   #:screen-blit
   #:screen-crop
   #:screen-write-lines
   #:screen-write-wrapped
   #:screen-write-aligned
   #:screen-to-string
   ;; box drawing
   #:screen-draw-box
   #:screen-draw-horizontal-line
   #:screen-draw-vertical-line
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
   ;; double-buffered renderer
   #:renderer
   #:make-renderer
   #:renderer-screen
   #:renderer-width
   #:renderer-height
   #:renderer-render
   #:renderer-clear
   #:renderer-resize
   ;; pty
   #:pty
   #:make-pty
   #:pty-process
   #:pty-stream
   #:pty-read
   #:pty-write
   #:pty-resize
   #:pty-alive-p
   #:pty-exit-code
   #:close-pty))
