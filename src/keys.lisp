(in-package #:cl-tty-kit)

(defstruct (key-event (:constructor %make-key-event
                                    (&key (type :character) code modifiers
                                     (kind :press) text shifted-key base-key)))
  "A decoded terminal key event with an event type, code, modifiers, kind,
optional associated text, and optional kitty shifted / base-layout alternates."
  (type :character :type keyword)
  code
  (modifiers nil :type list)
  (kind :press :type keyword)
  (text nil :type (or null string))
  (shifted-key nil :type (or null character))
  (base-key nil :type (or null character)))

(setf (documentation 'key-event-type 'function)
      "Return the event type of KEY-EVENT.")

(setf (documentation 'key-event-code 'function)
      "Return the code carried by KEY-EVENT.")

(setf (documentation 'key-event-modifiers 'function)
      "Return the normalized modifier list of KEY-EVENT.")

(setf (documentation 'key-event-kind 'function)
      "Return the kind of KEY-EVENT: :PRESS, :REPEAT, or :RELEASE. Terminals
report :REPEAT and :RELEASE only under the kitty keyboard protocol (see
ANSI-SET-KEYBOARD-ENHANCEMENTS); otherwise every event is :PRESS.")

(setf (documentation 'key-event-text 'function)
      "Return the text associated with KEY-EVENT, or NIL. Only the kitty keyboard
protocol's text-reporting mode supplies this -- the string a key would insert,
useful for international/IME input where it differs from the key code.")

(setf (documentation 'key-event-shifted-key 'function)
      "Return the shifted alternate of KEY-EVENT's key as a character, or NIL.
The kitty keyboard protocol reports this as the second sub-field of its key
field (e.g. `a' shifted is `A'); NIL otherwise.")

(setf (documentation 'key-event-base-key 'function)
      "Return the base-layout alternate of KEY-EVENT's key as a character, or NIL.
The kitty keyboard protocol reports this as the third sub-field of its key field
-- the key at that physical position on the base (e.g. US-QWERTY) layout -- for
layout-independent keybindings; NIL otherwise.")

(defun keyword-modifier-p (value)
  (keywordp value))

(defun unique-keyword-modifiers (modifiers)
  (let ((seen '()))
    (dolist (modifier (ensure-list* modifiers) (nreverse seen))
      (when (and (keyword-modifier-p modifier)
                 (not (member modifier seen :test #'eq)))
        (push modifier seen)))))

(defun normalize-modifiers (modifiers)
  "Return the keyword modifiers in MODIFIERS, de-duplicated and ordered by name.
Non-keyword entries are ignored, so equivalent modifier sets compare EQUAL
regardless of the order or duplicates in which they were supplied."
  (sort (unique-keyword-modifiers modifiers)
        #'string< :key #'symbol-name))

(defun modifiers-from-csi-number (number)
  (let ((mask (max 0 (1- (or number 1)))))
    (normalize-modifiers
     (append (when (logtest mask 1) '(:shift))
             (when (logtest mask 2) '(:alt))
             (when (logtest mask 4) '(:control))))))

(defun %assert-key-event-type (type)
  (unless (member type '(:character :special :paste) :test #'eq)
    (error "Key event TYPE ~S must be :CHARACTER, :SPECIAL, or :PASTE."
           type)))

(defun %assert-key-event-code (type code)
  (case type
    (:character
     (unless (characterp code)
       (error "Character key event CODE ~S must be a character." code)))
    (:special
     (unless (keywordp code)
       (error "Special key event CODE ~S must be a keyword." code)))
    (:paste
     (unless (stringp code)
       (error "Paste key event CODE ~S must be a string." code)))))

(defun %assert-key-event-kind (kind)
  (unless (member kind '(:press :repeat :release) :test #'eq)
    (error "Key event KIND ~S must be :PRESS, :REPEAT, or :RELEASE." kind)))

(defun %assert-optional-key-event-string (name value)
  (unless (or (null value) (stringp value))
    (error "Key event ~A ~S must be NIL or a string." name value)))

(defun %assert-optional-key-event-character (name value)
  (unless (or (null value) (characterp value))
    (error "Key event ~A ~S must be NIL or a character." name value)))

(defun %assert-key-event (event)
  (unless (key-event-p event)
    (error "EVENT ~S must be a key-event." event))
  event)

(defun make-key-event (&key (type :character) code modifiers (kind :press) text
                            shifted-key base-key)
  "Build a KEY-EVENT with normalized modifier ordering."
  (%assert-key-event-type type)
  (%assert-key-event-code type code)
  (%assert-key-event-kind kind)
  (%assert-optional-key-event-string "TEXT" text)
  (%assert-optional-key-event-character "SHIFTED-KEY" shifted-key)
  (%assert-optional-key-event-character "BASE-KEY" base-key)
  (%make-key-event :type type
                   :code code
                   :modifiers (normalize-modifiers modifiers)
                   :kind kind
                   :text text
                   :shifted-key shifted-key
                   :base-key base-key))

(defun %key-event (type code &optional modifiers (kind :press) text)
  (make-key-event :type type :code code :modifiers modifiers
                  :kind kind :text text))

(defun %modifier-prefix (modifiers)
  "Return the `C-'/`M-'/`S-' prefix string for MODIFIERS, in Ctrl-Alt-Shift
order regardless of how they were stored."
  (with-output-to-string (out)
    (dolist (entry '((:control . "C-") (:alt . "M-") (:shift . "S-")))
      (when (member (car entry) modifiers :test #'eq)
        (write-string (cdr entry) out)))))

(defun %format-key-keyword (keyword)
  "Render a :SPECIAL key code keyword as a label, mapping :CONTROL-x to `C-x'
and otherwise capitalizing hyphen-delimited words (:PAGE-UP -> \"Page-Up\")."
  (let ((name (symbol-name keyword)))
    (if (and (= (length name) 9)
             (string= "CONTROL-" name :end2 8))
        (format nil "C-~A" (char-downcase (char name 8)))
        (string-capitalize name))))

(defun %key-event-body (event)
  (let ((type (key-event-type event))
        (code (key-event-code event)))
    (case type
      (:character (string code))
      (:paste (format nil "<paste ~D bytes>"
                      (if (stringp code) (length code) 0)))
      (t (cond
           ((characterp code) (string code))
           ((keywordp code) (%format-key-keyword code))
           (t (princ-to-string code)))))))

(defun key-event->string (event)
  "Return a human-readable label for EVENT, such as \"C-a\", \"S-Up\", \"Enter\",
\"x\", or \"<paste 12 bytes>\". Modifiers become a `C-'/`M-'/`S-' prefix in
Ctrl-Alt-Shift order; a :SPECIAL code keyword is capitalized (with :CONTROL-x
shown as `C-x'); a :PASTE event reports its payload length."
  (%assert-key-event event)
  (concatenate 'string
               (%modifier-prefix (key-event-modifiers event))
               (%key-event-body event)))
