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

(defparameter *canonical-modifier-order*
  '(:alt :control :shift)
  "Preferred order for normalized modifier lists.")

(defun keyword-modifier-p (value)
  (keywordp value))

(defun unique-keyword-modifiers (modifiers)
  (let ((seen '()))
    (dolist (modifier (ensure-list* modifiers) (nreverse seen))
      (when (and (keyword-modifier-p modifier)
                 (not (member modifier seen :test #'eq)))
        (push modifier seen)))))

(defun collect-canonical-modifiers (modifiers)
  (let ((result '()))
    (dolist (modifier *canonical-modifier-order* (nreverse result))
      (when (member modifier modifiers :test #'eq)
        (push modifier result)))))

(defun collect-extra-modifiers (modifiers)
  (let ((result '()))
    (dolist (modifier modifiers (nreverse result))
      (unless (member modifier *canonical-modifier-order* :test #'eq)
        (push modifier result)))))

(defun normalize-modifiers (modifiers)
  (let ((unique (unique-keyword-modifiers modifiers)))
    (append (collect-canonical-modifiers unique)
            (collect-extra-modifiers unique))))

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
