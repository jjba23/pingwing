;;; pingwing -- render the frames of the README's showcase.
;;;
;;; This is a build-time helper, not part of the application: it calls the very
;;; same template modules a delivery calls and writes what they return to
;;; tmp/demo/, so the picture in the manual is the code's own output rather
;;; than a mock-up that can drift away from it.
;;;
;;; Two copies of each mail are written.  tmp/demo/frames/ holds what the
;;; template returned, byte for byte -- that is the artefact, and what a test
;;; or a curious reader should look at.  tmp/demo/shots/ holds the same
;;; document with one addition, a rule telling the page to fill the height of
;;; the window the screenshot is taken in, so that a mail shorter than the
;;; window does not leave the area under it unpainted.  Nothing else about the
;;; message changes, and only the second copy is ever photographed.
;;;
;;; `docs/make-demo-gif.sh' runs this and then the browser and the encoder; run
;;; it from the repository root, inside the project's environment:
;;;
;;;   guix shell -m manifest.scm -- ./docs/make-demo-gif.sh

(add-to-load-path (string-append (getcwd) "/lib"))

(use-modules (ice-9 textual-ports)
             (ice-9 format)
             (ice-9 string-fun)
             (sxml simple)
             (pingwing templates password-reset)
             (pingwing templates system-alert)
             (pingwing templates lucidplan-new-ticket))

(define frames-dir "tmp/demo/frames")
(define shots-dir "tmp/demo/shots")

;; What makes a page as tall as the window it is looked at in.  The mail's own
;; inline styles paint the body, so giving it a minimum height of one viewport
;; is what carries its gradient to the bottom edge of the shot.
(define viewport-fill
  "<style>html{min-height:100%;}body{min-height:100vh;}</style>")

;; Both directories exist after this line, and asking for that again is not an
;; error (`mkdir -p'), so a rerun does not have to clean up first.
(system* "mkdir" "-p" frames-dir shots-dir)

(define (write-file path contents)
  (call-with-output-file path
    (lambda (port)
      ;; The templates return a document that begins at <html>; a browser reads
      ;; a page with no doctype in quirks mode, so the doctype is put back for
      ;; the screenshot only.
      (display "<!DOCTYPE html>\n" port)
      (display contents port)))
  (format #t "wrote ~a~%" path))

(define (render! name html)
  (write-file (format #f "~a/~a.html" frames-dir name) html)
  (write-file (format #f "~a/~a.html" shots-dir name)
              (string-replace-substring html "</head>"
                                        (string-append viewport-fill
                                                       "</head>"))))

;; The ticket notice: what lucidplan asks pingwing to send when somebody opens
;; a ticket in one of its projects, and the message the showcase opens on.
(render! "1-new-ticket"
         (lucidplan-new-ticket-html-template
          #:system-name "Lucidplan"
          #:project-name "Pingwing"
          #:project-human-id "pingwing"
          #:ticket-human-id 12
          #:ticket-title "Retry the SMTP delivery"
          #:ticket-type "bug"
          #:ticket-status "open"
          #:priority 2
          #:author "John Doe"
          #:assignee "Nina"
          #:description
          "A flaky connection made a mail go missing; the task should be tried again instead of being given up on."
          #:ticket-url
          "https://lucidplan.jointhefreeworld.org/pingwing/tickets/12"))

(render! "2-password-reset"
         (password-reset-html-template
          #:system-name "WikiMusic"
          #:user "john.doe@example.org"
          #:reset-link
          "https://wikimusic.jointhefreeworld.org/reset/2f6a4d3e1c2b4a5f9e8d"))

(render! "3-system-alert"
         (system-alert-html-template
          #:system-name "Pingwing"
          #:alert-value
          "disk usage at 94% on mail-01\nSMTP queue depth 128\ndelivery latency p95 4.2s"))

(format #t "~a frames rendered~%" 3)
