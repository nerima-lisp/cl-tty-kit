(in-package #:cl-tty-kit)

(defstruct (key-event (:constructor %make-key-event
                                    (&key (type :character) code modifiers)))
  "A decoded terminal key event with an event type, code, and modifiers."
  (type :character :type keyword)
  code
  (modifiers nil :type list))

(setf (documentation 'key-event-type 'function)
      "Return the event type of KEY-EVENT.")

(setf (documentation 'key-event-code 'function)
      "Return the code carried by KEY-EVENT.")

(setf (documentation 'key-event-modifiers 'function)
      "Return the normalized modifier list of KEY-EVENT.")

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

(defun make-key-event (&key (type :character) code modifiers)
  "Build a KEY-EVENT with normalized modifier ordering."
  (%make-key-event :type type
                   :code code
                   :modifiers (normalize-modifiers modifiers)))

(defun %key-event (type code &optional modifiers)
  (make-key-event :type type :code code :modifiers modifiers))
