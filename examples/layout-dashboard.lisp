(require :asdf)

(load (merge-pathnames #P"bootstrap.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(in-package #:cl-user)

(defvar *cl-tty-kit-run-example-on-load* t)

(defun %dashboard-panel (screen rect title)
  "Draw a titled single-border box over RECT and return its inset interior."
  (cl-tty-kit:screen-draw-box screen
                              (cl-tty-kit:rect-x rect) (cl-tty-kit:rect-y rect)
                              (cl-tty-kit:rect-width rect) (cl-tty-kit:rect-height rect)
                              :border :single :title title)
  (cl-tty-kit:rect-inset rect :all 1))

(defun layout-dashboard-example ()
  "Lay out a header / sidebar+main / footer dashboard with LAYOUT-SPLIT constraints."
  (let* ((screen (cl-tty-kit:make-screen 40 10))
         (root (cl-tty-kit:make-rect :width 40 :height 10)))
    ;; Rows: fixed 3-tall header and footer, the body fills the middle.
    (destructuring-bind (header body footer)
        (cl-tty-kit:layout-split root :vertical '((:length 3) (:fill 1) (:length 3)))
      ;; Columns: a fixed 12-wide sidebar and a filling main pane, 1 cell apart.
      (destructuring-bind (sidebar main)
          (cl-tty-kit:layout-split body :horizontal '((:length 12) (:fill 1))
                                   :spacing 1)
        (cl-tty-kit:screen-write-aligned
         screen (%dashboard-panel screen header " header ") "cl-tty-kit"
         :align :center)
        (cl-tty-kit:screen-write-aligned
         screen (%dashboard-panel screen sidebar " nav ") "menu"
         :align :center)
        (cl-tty-kit:screen-write-aligned
         screen (%dashboard-panel screen main " main ") "content"
         :align :center :vertical :middle)
        (cl-tty-kit:screen-write-aligned
         screen (%dashboard-panel screen footer " foot ") "status"
         :align :center)))
    (cl-tty-kit:render-screen screen)))

(defun run-layout-dashboard-example ()
  (format t "~A~%" (layout-dashboard-example)))

(when *cl-tty-kit-run-example-on-load*
  (run-layout-dashboard-example))
