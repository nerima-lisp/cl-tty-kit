(in-package #:cl-tty-kit)

;;; --------------------------------------------------------------------------
;;; Non-blocking stream input seam
;;;
;;; The realtime tick loop deliberately leaves readiness policy to callers.
;;; This small adapter covers the common single-terminal case while retaining
;;; the incremental decoder across ticks (including split escape sequences).
;;; --------------------------------------------------------------------------

(defun %validate-input-poll-limit (limit)
  (unless (and (integerp limit) (plusp limit))
    (error "INPUT poll limit must be a positive integer, got ~S." limit))
  limit)

(defun make-stream-input-poller (stream &key (decoder (make-input-decoder))
                                             (limit 4096))
  "Return a realtime-loop POLL-INPUT callback for STREAM.

The returned function accepts the usual `(state timeout)' arguments, reads up
to LIMIT currently available characters with READ-CHAR-NO-HANG, and returns
the decoded events from DECODER. It returns NIL when no character is ready.
DECODER is retained between calls so an escape sequence split across frames is
decoded correctly. TIMEOUT is accepted for direct use as a tick-loop callback
but does not cause this stream adapter to block; callers needing multiplexed
readiness should keep their own poller and call DECODE-INPUT-CHUNK directly."
  (unless (input-stream-p stream)
    (error "INPUT poll stream must be an input stream, got ~S." stream))
  (unless (typep decoder 'input-decoder)
    (error "INPUT poll decoder must be an INPUT-DECODER, got ~S." decoder))
  (setf limit (%validate-input-poll-limit limit))
  ;; Keep the character chunk alive across ticks.  A string stream plus
  ;; GET-OUTPUT-STREAM-STRING would allocate on every poll, including idle
  ;; polls, which is a noticeable cost for long-running dashboards.
  (let ((chunk (make-array limit
                           :element-type 'character
                           :adjustable t
                           :fill-pointer 0)))
    (lambda (state timeout)
      (declare (ignore state timeout))
      (setf (fill-pointer chunk) 0)
      (loop repeat limit
            for character = (read-char-no-hang stream nil nil)
            while character
            do (vector-push character chunk))
      (and (plusp (length chunk))
           (decode-input-chunk decoder chunk)))))
