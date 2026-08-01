(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; Minimal moving-entity helper
;;;
;;; An ENTITY is just a position plus a velocity, and ENTITY-TICK is the one
;;; operation on it: add the velocity to the position, then, if the new
;;; position falls outside a caller-given WIDTH by HEIGHT screen, call the
;;; entity's ON-EXIT callback once per edge it left. Everything past that --
;;; how many entities exist, how they are stored, what "respawn" or "remove"
;;; means -- is left to the caller's own Lisp (a list, a loop), deliberately.
;;; This is not a z-order/layer system, an ECS, or a particle system; a caller
;;; that wants compositing order controls it by choosing SPRITE-BLIT call
;;; order (paint back to front), not by anything this file provides.
;;; --------------------------------------------------------------------------

(defstruct (entity (:constructor %make-entity (&key x y dx dy on-exit)) (:copier nil))
  "A moving point: an (X, Y) position, a (DX, DY) velocity applied once per
ENTITY-TICK, and an optional ON-EXIT callback fired when the position leaves a
screen's bounds."
  (x 0 :type real)
  (y 0 :type real)
  (dx 0 :type real)
  (dy 0 :type real)
  (on-exit nil :type (or null function)))

(setf (documentation 'entity-x 'function) "Return the column position of ENTITY.")
(setf (documentation 'entity-y 'function) "Return the row position of ENTITY.")
(setf (documentation 'entity-dx 'function) "Return the per-tick column velocity of ENTITY.")
(setf (documentation 'entity-dy 'function) "Return the per-tick row velocity of ENTITY.")
(setf (documentation 'entity-on-exit 'function)
      "Return ENTITY's off-bounds callback, or NIL.")

(define-simple-assert %assert-entity (entity)
  (entity-p entity)
  "Expected an ENTITY, got ~S." entity)

(define-simple-assert %assert-entity-real (name value)
  (realp value)
  "Entity ~A ~S must be a real number." name value)

(define-simple-assert %assert-entity-callback (callback)
  (or (null callback) (functionp callback))
  "Entity :ON-EXIT ~S must be NIL or a function." callback)

(defun make-entity (&key (x 0) (y 0) (dx 0) (dy 0) on-exit)
  "Create an ENTITY at position (X, Y) with velocity (DX, DY).
ON-EXIT, when supplied, must be a function of two arguments (ENTITY EDGE),
called by ENTITY-TICK once per screen edge ENTITY's position has just left,
EDGE one of :LEFT, :RIGHT, :TOP, or :BOTTOM. X, Y, DX, and DY must be real
numbers."
  (%assert-entity-real :x x)
  (%assert-entity-real :y y)
  (%assert-entity-real :dx dx)
  (%assert-entity-real :dy dy)
  (%assert-entity-callback on-exit)
  (%make-entity :x x :y y :dx dx :dy dy :on-exit on-exit))

(defun entity-tick (entity width height)
  "Advance ENTITY's position by its velocity, returning ENTITY.
WIDTH and HEIGHT describe the screen bounds to check the new position
against; they are not stored on ENTITY, so successive calls can check
different bounds (e.g. after a terminal resize).

When the new position falls outside [0, WIDTH) by [0, HEIGHT), ENTITY's
ON-EXIT callback (if any) is called once per violated edge, in the order
:LEFT, :RIGHT, :TOP, :BOTTOM, as (FUNCALL ON-EXIT ENTITY EDGE) -- so an
entity that exits through a corner fires the callback twice, once for each
edge. A caller wanting to respawn or remove the entity does so from within
ON-EXIT; ENTITY-TICK itself never removes or mutates the callback."
  (%assert-entity entity)
  (%assert-entity-real :width width)
  (%assert-entity-real :height height)
  (incf (entity-x entity) (entity-dx entity))
  (incf (entity-y entity) (entity-dy entity))
  (let ((callback (entity-on-exit entity)))
    (when callback
      (when (< (entity-x entity) 0)
        (funcall callback entity :left))
      (when (>= (entity-x entity) width)
        (funcall callback entity :right))
      (when (< (entity-y entity) 0)
        (funcall callback entity :top))
      (when (>= (entity-y entity) height)
        (funcall callback entity :bottom))))
  entity)
