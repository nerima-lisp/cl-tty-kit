(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; Shell integration and desktop notification OSC sequences
;;;
;;; OSC 133 semantic prompt marks, OSC 7 working-directory reports, and the
;;; OSC 9 / 777 / 99 notification dialects. All are ST-terminated and reuse
;;; ansi-osc.lisp's sanitization.
;;; --------------------------------------------------------------------------
(defun %osc-st (body)
  (format nil "~C]~A~C\\" +escape+ body +escape+))

(defun ansi-prompt-start ()
  "Return the OSC 133 mark `ESC ] 133 ; A ST' that a shell emits just before
drawing its prompt."
  (%osc-st "133;A"))

(defun ansi-command-start ()
  "Return the OSC 133 mark `ESC ] 133 ; B ST' that ends the prompt and starts
the command line the user types."
  (%osc-st "133;B"))

(defun ansi-command-output-start ()
  "Return the OSC 133 mark `ESC ] 133 ; C ST' emitted after the command is
submitted, just before its output begins."
  (%osc-st "133;C"))

(defun ansi-command-finished (&optional exit-status)
  "Return the OSC 133 mark that closes a command: `ESC ] 133 ; D ST', or
`ESC ] 133 ; D ; EXIT-STATUS ST' when EXIT-STATUS (a non-negative integer) is
given."
  (cond
    ((null exit-status) (%osc-st "133;D"))
    ((typep exit-status '(integer 0 *))
     (%osc-st (format nil "133;D;~D" exit-status)))
    (t (error "OSC 133 exit status must be a non-negative integer: ~S." exit-status))))

(defun %uri-unreserved-octet-p (octet)
  (or (<= (char-code #\A) octet (char-code #\Z))
      (<= (char-code #\a) octet (char-code #\z))
      (<= (char-code #\0) octet (char-code #\9))
      (member octet (load-time-value (map 'list #'char-code "-._~")))))

(defun %percent-encode (string &key keep-slash)
  "Percent-encode the UTF-8 octets of STRING, leaving RFC 3986 unreserved
characters (and `/' when KEEP-SLASH) literal. Hex digits are uppercase."
  (with-output-to-string (out)
    (loop for octet across (sb-ext:string-to-octets string :external-format :utf-8)
          do (if (or (%uri-unreserved-octet-p octet)
                     (and keep-slash (= octet (char-code #\/))))
                 (write-char (code-char octet) out)
                 (format out "%~2,'0X" octet)))))

(defun ansi-set-working-directory (path &key (host (machine-instance)))
  "Return the OSC 7 sequence `ESC ] 7 ; file://HOST/PATH ST' reporting the
current working directory, so a terminal can open new tabs or splits there.
PATH must be an absolute path string (starting with `/'). Its UTF-8 octets are
percent-encoded except RFC 3986 unreserved characters and `/'. HOST defaults to
MACHINE-INSTANCE; it is stripped of control characters and percent-encoded the
same way, `/' included. A NIL HOST yields an empty authority (`file:///PATH')."
  (unless (and (stringp path) (plusp (length path)) (char= (char path 0) #\/))
    (error "OSC 7 path must be a string starting with \"/\": ~S." path))
  (%osc-st (format nil "7;file://~A~A"
                   (if host (%percent-encode (%sanitize-osc-string host)) "")
                   (%percent-encode path :keep-slash t))))

(defun %kitty-identifier-p (string)
  (and (plusp (length string))
       (every (lambda (character)
                (or (char<= #\A character #\Z)
                    (char<= #\a character #\z)
                    (char<= #\0 character #\9)
                    (find character "_+.-")))
              string)))

;;; kitty's spec: "The size of the payload must be no longer than 2048 bytes,
;;; before being encoded or 4096 encoded bytes." The payload is the part after
;;; the second `;'; we send plain UTF-8 (no e=1), so the 2048-byte figure
;;; applies. "You can specify the title or body multiple times and the
;;; terminal emulator will concatenate them", with chunks joined by a shared
;;; `i' and held back while `d=0'.
;;; https://sw.kovidgoyal.net/kitty/desktop-notifications/
(defconstant +osc-99-max-payload-octets+ 2048)

(defun %utf-8-octet-count (character)
  (let ((code (char-code character)))
    (cond ((< code #x80) 1)
          ((< code #x800) 2)
          ((< code #x10000) 3)
          (t 4))))

(defun %osc-99-chunks (string)
  "Split STRING at character boundaries into substrings of at most
+OSC-99-MAX-PAYLOAD-OCTETS+ UTF-8 octets each. An empty STRING yields one
empty chunk."
  (let ((chunks '())
        (start 0)
        (octets 0))
    (loop for index from 0 below (length string)
          for size = (%utf-8-octet-count (char string index))
          do (when (> (+ octets size) +osc-99-max-payload-octets+)
               (push (subseq string start index) chunks)
               (setf start index
                     octets 0))
             (incf octets size))
    (push (subseq string start) chunks)
    (nreverse chunks)))

(defun %osc-99-notification (body title id)
  (let ((body-chunks (%osc-99-chunks (%sanitize-osc-string body)))
        (title-chunks (and title (%osc-99-chunks (%sanitize-osc-string title))))
        (id (and id (princ-to-string id))))
    (when (and id (not (%kitty-identifier-p id)))
      (error "OSC 99 notification id must match [A-Za-z0-9_+.-]+: ~S." id))
    (if (and (null title-chunks) (null (rest body-chunks)))
        (%osc-st (format nil "99;~@[i=~A:~]p=body;~A" id (first body-chunks)))
        ;; Several chunks: only a shared id lets kitty join them, so one is
        ;; required here.
        (let ((id (or id "1")))
          (with-output-to-string (out)
            (dolist (chunk title-chunks)
              (write-string (%osc-st (format nil "99;i=~A:d=0:p=title;~A" id chunk)) out))
            (loop for (chunk . more) on body-chunks
                  do (write-string (%osc-st (format nil "99;i=~A:d=~:[1~;0~]:p=body;~A"
                                                    id more chunk))
                                   out)))))))

(defun ansi-notify (body &key title (protocol :osc-777) id)
  "Return a desktop-notification sequence showing BODY, optionally with TITLE.
PROTOCOL selects the dialect; all payloads are stripped of control characters.

:OSC-777 (default; from rxvt-unicode):
  `ESC ] 777 ; notify ; TITLE ; BODY ST'. TITLE defaults to empty and has `;'
  removed, since `;' separates the fields; BODY may contain `;'.
:OSC-9 (from iTerm2): `ESC ] 9 ; TEXT ST', where TEXT
  is BODY or `TITLE: BODY' because OSC 9 has no title field. Terminals that
  implement ConEmu's OSC 9 subcommands (such as `9;4' progress) read a TEXT
  that starts with digits and `;' as a subcommand rather than a notification.
:OSC-99 (kitty): `ESC ] 99 ; p=body ; BODY ST' without TITLE. With TITLE, two
  sequences sharing an id: `i=ID:d=0:p=title' then `i=ID:d=1:p=body'. ID must
  match [A-Za-z0-9_+.-]+; it is omitted when not given and there is no
  TITLE, and defaults to \"1\" with a TITLE, so pass distinct ids to keep
  successive titled notifications from replacing each other. kitty limits
  each payload to 2048 bytes, so a TITLE or BODY longer than that in UTF-8 is
  split at character boundaries into several `p=title' or `p=body' sequences
  sharing the id (again defaulting to \"1\"), each `d=0' except the last body
  chunk. ID is ignored by the other protocols."
  (case protocol
    (:osc-777
     (%osc-st (format nil "777;notify;~A;~A"
                      (remove #\; (%sanitize-osc-string (or title "")))
                      (%sanitize-osc-string body))))
    (:osc-9
     (%osc-st (format nil "9;~@[~A: ~]~A"
                      (and title (%sanitize-osc-string title))
                      (%sanitize-osc-string body))))
    (:osc-99
     (%osc-99-notification body title id))
    (t (error "Unknown notification protocol ~S; expected :OSC-777, :OSC-9, or :OSC-99."
              protocol))))
