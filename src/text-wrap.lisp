(in-package #:cl-tty-kit)

(defmacro %hard-split-word (word width)
  "Split WORD into a list of chunks each at most WIDTH columns wide.
Used only for a single word longer than a full line. A glyph wider than WIDTH on
its own becomes a lone over-width chunk rather than causing an endless loop."
  `(let ((word ,word) (width ,width))
     (let ((chunks '())
           (length (length word))
           (index 0))
       (loop while (< index length)
             do (let ((next (%width-prefix-end word width :start index)))
                  (when (= next index)
                    (setf next (1+ index)))
                  (push (subseq word index next) chunks)
                  (setf index next)))
       (nreverse chunks))))

(defun %split-on-char (string char)
  (let ((parts '())
        (start 0)
        (length (length string)))
    (loop for position = (position char string :start start)
          do (push (subseq string start (or position length)) parts)
             (if position
                 (setf start (1+ position))
                 (return)))
    (nreverse parts)))

(defun %call-with-wrapped-paragraph-lines (paragraph width continuation
                                             &key (start 0) (end (length paragraph)))
  "Call CONTINUATION for each wrapped line in PARAGRAPH.

CONTINUATION returns true to continue or NIL to stop. Chunks retain source
ranges while wrapping, so only the callback boundary materializes a line."
  (let ((current-chunks (list))
        (current-width 0))
    (labels ((current-line ()
               (with-output-to-string (out)
                 (loop for chunk in (nreverse current-chunks)
                       for first = t then nil
                       do (unless first (write-char #\Space out))
                          (write-string paragraph out
                                        :start (car chunk)
                                        :end (cdr chunk)))))
             (emit-current-line ()
               (unless (funcall continuation (current-line))
                 (return-from %call-with-wrapped-paragraph-lines nil))
               (setf current-chunks (list)
                     current-width 0))
             (place (chunk-start chunk-end chunk-width)
               (setf current-chunks (list (cons chunk-start chunk-end))
                     current-width chunk-width))
             (append-chunk (chunk-start chunk-end chunk-width)
               (push (cons chunk-start chunk-end) current-chunks)
               (setf current-width (+ current-width 1 chunk-width)))
             (add-chunk (chunk-start chunk-end chunk-width)
               (cond
                 ((null current-chunks)
                  (place chunk-start chunk-end chunk-width))
                 ((<= (+ current-width 1 chunk-width) width)
                  (append-chunk chunk-start chunk-end chunk-width))
                 (t
                  (emit-current-line)
                  (place chunk-start chunk-end chunk-width)))))
      ;; Stream words so a consumer can stop before scanning later input.
      (loop with cursor = start
            while (< cursor end)
            for word-end = (or (position #\Space paragraph
                                         :start cursor
                                         :end end)
                               end)
            do (when (> word-end cursor)
                 (let ((word-width (string-width paragraph
                                                 :start cursor
                                                 :end word-end)))
                   (if (> word-width width)
                       (loop with index = cursor
                             while (< index word-end)
                             for next = (%width-prefix-end paragraph width
                                                           :start index
                                                           :end word-end)
                             do (when (= next index)
                                  (setf next (1+ index)))
                                (add-chunk index next
                                           (%string-cell-width paragraph
                                                               :start index
                                                               :end next))
                                (setf index next))
                       (add-chunk cursor word-end word-width))))
               (setf cursor (1+ word-end)))
      (funcall continuation (if current-chunks (current-line) "")))))

(defun chop-string (string width)
  "Return STRING cut into a list of pieces each at most WIDTH terminal columns.
Unlike WRAP-STRING this is a hard chop at column boundaries with no word breaking;
a glyph wider than WIDTH becomes a lone over-width piece. An empty STRING yields
an empty list. WIDTH must be a positive integer."
  (%assert-layout-string "STRING" string)
  (%assert-layout-width "WIDTH" width :positive t)
  (if (zerop (length string))
      '()
      (%hard-split-word string width)))

(defmacro %call-with-wrapped-lines (string width continuation)
  "Call CONTINUATION for each line produced by validated STRING and WIDTH.

Stop immediately when CONTINUATION returns NIL, avoiding work for lines a
consumer will not observe."
  `(let ((string ,string) (width ,width) (continuation ,continuation))
     (let ((start 0)
           (end (length string)))
       (loop for newline = (position #\Newline string :start start :end end)
             for paragraph-end = (or newline end)
             unless (%call-with-wrapped-paragraph-lines
                     string width continuation :start start :end paragraph-end)
               do (return nil)
             do (if newline
                    (setf start (1+ newline))
                    (return t))))))

(defmacro %wrap-string-unchecked (string width)
  "Wrap validated STRING to validated positive WIDTH."
  `(let ((string ,string) (width ,width))
     (let ((lines '()))
       (%call-with-wrapped-lines
        string width
        (lambda (line)
          (push line lines)
          t))
       (nreverse lines))))

(defun wrap-string (string width)
  "Return a list of lines wrapping STRING to at most WIDTH terminal columns each.
Words -- runs between spaces -- are kept whole and greedily packed; a single word
wider than WIDTH is hard-split at a column boundary. Runs of spaces collapse to a
single separator, but embedded newlines are honored as forced breaks, so a blank
line in the input yields an empty string in the result. WIDTH must be positive."
  (%assert-layout-string "STRING" string)
  (%assert-layout-width "WIDTH" width :positive t)
  (%wrap-string-unchecked string width))
