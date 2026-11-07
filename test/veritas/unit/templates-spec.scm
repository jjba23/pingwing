;; pingwing - the free and open Lisp-powered notification nexus
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; The templates' own promises about what they always say: a reader is named,
;;; the thing the mail is about is named, and the link is one a click can
;;; follow.  The styling is checked in the same place, since it is what a
;;; message looks like when it arrives -- one style block, inline, with the
;;; frosted panel the family's mails share.

(define-module (veritas unit templates-spec)
  #:use-module (veritas veritas)
  #:use-module (ice-9 format)
  #:use-module (ice-9 regex)
  #:use-module (srfi srfi-1)
  #:use-module (pingwing css)
  #:use-module (pingwing html)
  #:use-module (pingwing mail)
  #:use-module (pingwing templates password-reset)
  #:use-module (pingwing templates system-alert)
  #:use-module (pingwing templates lucidplan-new-ticket)
  #:export (spec))

;;; ====== password reset ======

(define password-reset-suite
  (let ((html (password-reset-html-template #:system-name "WikiMusic"
                                            #:user "joe@x.y"
                                            #:reset-link "https://x/y")))
    (suite "password reset template"
           (test "the account is named"
                 (assert-contains #:name
                                  "the reader is told whose account this is"
                                  #:expect html
                                  #:got "joe@x.y"))
           (test "the link is present"
                 (assert-contains #:name "the reset link is in the mail"
                                  #:expect html
                                  #:got "https://x/y"))
           (test "the style is inline"
                 (assert-contains #:name
                  "a mail client that drops stylesheets still sees it"
                  #:expect html
                  #:got "style="))
           (test "the frosted panel is there"
                 (assert-contains #:name
                  "the panel the family's mails share is drawn"
                  #:expect html
                  #:got "pw-panel")))))

;;; ====== system alert ======

(define system-alert-suite
  (let ((html (system-alert-html-template #:system-name "X"
                                          #:alert-value "disk full")))
    (suite "system alert template"
           (test "the alert is shown"
                 (assert-contains #:name "what went wrong is in the mail"
                                  #:expect html
                                  #:got "disk full"))
           (test "the system is named"
                 (assert-contains #:name
                                  "which system raised it is in the mail"
                                  #:expect html
                                  #:got "X")))))

;;; ====== lucidplan, new ticket ======

(define new-ticket-suite
  (let* ((html (lucidplan-new-ticket-html-template #:system-name "Lucidplan"
                #:project-name "Pingwing"
                #:ticket-human-id 12
                #:ticket-title "Fix the SMTP retry"
                #:ticket-type "bug"
                #:priority 2
                #:author "joe"
                #:ticket-url "https://lucidplan/x/ticket/12"))
         (plain (lucidplan-new-ticket-plain-template #:system-name "Lucidplan"
                 #:project-name "Pingwing"
                 #:ticket-human-id 12
                 #:ticket-title "Fix the SMTP retry"
                 #:ticket-url "https://lucidplan/x/ticket/12")))
    (suite "lucidplan new-ticket template"
           (test "the HTML part names the project, the ticket and the link"
                 (assert-contains #:name "the project is named"
                                  #:expect html
                                  #:got "Pingwing")
                 (assert-contains #:name "the ticket number reads as #12"
                                  #:expect html
                                  #:got "#12")
                 (assert-contains #:name "the title is shown"
                                  #:expect html
                                  #:got "Fix the SMTP retry")
                 (assert-contains #:name "the link is shown"
                                  #:expect html
                                  #:got "https://lucidplan/x/ticket/12"))
           (test "the plain part says the same thing"
                 (assert-contains #:name "the plain part names the ticket too"
                                  #:expect plain
                                  #:got "Fix the SMTP retry")
                 (assert-contains #:name "the plain part names the project"
                                  #:expect plain
                                  #:got "Pingwing")))))

;;; ====== the document a mail client is handed ======

;; A message's HTML part is a whole document, and the first line of it says so.
;; Told nothing, a client reads the message as legacy HTML -- quirks mode --
;; where the fixed 600px panel and the table the message is laid out with are
;; sized by rules the styles never asked for.  The doctype is written by
;; `mail-document->string', which every template serialises through, and that is
;; exactly what is asserted here: it is not enough that today's three templates
;; have it, a fourth has to come through the same door.
(define (occurrences-in needle haystack)
  "How many times NEEDLE appears in HAYSTACK."
  (let loop
    ((from 0)
     (seen 0))
    (let ((at (string-contains haystack needle from)))
      (if at
          (loop (+ at
                   (string-length needle))
                (+ seen 1)) seen))))

(define document-suite
  (let ((ticket (lucidplan-new-ticket-html-template #:system-name "Lucidplan"
                 #:project-name "Pingwing"
                 #:ticket-human-id 12
                 #:ticket-title "Fix the SMTP retry"
                 #:ticket-url "https://lucidplan/x/ticket/12"))
        (reset (password-reset-html-template #:system-name "WikiMusic"
                                             #:user "joe@x.y"
                                             #:reset-link "https://x/y"))
        (alert (system-alert-html-template #:system-name "X"
                                           #:alert-value "disk full")))
    (suite "the document a mail client is handed"
           (test "every message opens with the doctype"
                 (assert-true (string-prefix? (string-append mail-doctype
                                                             "<html") ticket)
                              #:name "the ticket notice is a whole document")
                 (assert-true (string-prefix? (string-append mail-doctype
                                                             "<html") reset)
                              #:name "the reset mail is a whole document")
                 (assert-true (string-prefix? (string-append mail-doctype
                                                             "<html") alert)
                              #:name "the alert is a whole document"))
           (test "and says it only once"
                 (assert-false (string-contains (substring ticket 1)
                                                "<!DOCTYPE")
                               #:name
                               "the doctype is at the front, not repeated"))
           ;; The two halves have to agree: the document writes the doctype and
           ;; the assembler wraps the part without writing one of its own, so
           ;; the message a client receives opens the HTML part with it.  This
           ;; is the check that would fail if either half changed its mind.
           (test "the message a client receives opens with it"
                 (let ((message (build-mail-message #:id "the-id"
                                                    #:from-name "No Reply"
                                                    #:from-address "n@x.y"
                                                    #:to-name "Joe"
                                                    #:to-address "j@x.y"
                                                    #:subject "Hi"
                                                    #:body "plain body"
                                                    #:body-html ticket)))
                   (assert-true (string-contains message
                                                 "<!DOCTYPE html>\r\n<html")
                    #:name "the doctype opens the HTML part of the message")
                   (assert-equal #:name
                                 "the message carries exactly one doctype"
                                 #:expect 1
                                 #:got (occurrences-in "<!DOCTYPE" message)))))))

;;; ====== the markup a mail client is handed ======

;; `sxml->xml' writes an element that has no children as a self-closing tag --
;; `<div ... />' -- which is XML, not HTML: an HTML parser reads it as an
;; *opening* tag and makes everything after it its children.  A message that did
;; that arrived as an empty card, because the panel's whole body ended up inside
;; the six-pixel accent bar it is clipped by.  So it is asserted rather than
;; assumed, over every element that may hold something: only the void elements of
;; a document's head are allowed to close themselves.
(define self-closed-non-void
  "<(div|span|p|table|tr|td|th|h1|h2|a)[^>]*/>")

(define markup-suite
  (let ((ticket (lucidplan-new-ticket-html-template #:system-name "Lucidplan"
                 #:project-name "Pingwing"
                 #:ticket-human-id 12
                 #:ticket-title "Fix the SMTP retry"
                 #:ticket-url "https://lucidplan/x/ticket/12"))
        (reset (password-reset-html-template #:system-name "WikiMusic"
                                             #:user "joe@x.y"
                                             #:reset-link "https://x/y"))
        (alert (system-alert-html-template #:system-name "X"
                                           #:alert-value "disk full")))
    (suite "the markup a mail client is handed"
           (test "nothing is closed before it has been opened"
                 (assert-not-matches #:name
                  "the ticket notice is not swallowed by its own accent"
                  #:pattern self-closed-non-void
                  #:got ticket)
                 (assert-not-matches #:name
                  "the reset mail is not swallowed by its own rule"
                  #:pattern self-closed-non-void
                  #:got reset)
                 (assert-not-matches #:name
                                     "the alert is not swallowed either"
                                     #:pattern self-closed-non-void
                                     #:got alert)))))

;;; ====== what the dark override can reach ======

;; The head's media query re-points *classes* at the dark palette, and an
;; inline style outranks a rule of the page, so an element that writes a colour
;; without wearing a class is an element the dark reading cannot reach.  That is
;; how the fact rows and both links once arrived near-invisible in a dark client:
;; they carried a colour and no class, and no rule in the head could touch them.
;;
;; Two things are therefore asserted over every message: nothing paints unless it
;; wears a class, and every class it wears is a named style -- which is what
;; gives the override its rule.  A style added to `mail-styles' reaches both
;; readings by construction; a colour added anywhere else fails here.

(define painting-properties
  '("color:" "background"
    "border:"
    "border-top:"
    "border-right:"
    "border-bottom:"
    "border-left:"
    "box-shadow:"))

(define (tags html)
  "Every `<tag ...' in HTML, without its closing angle bracket."
  (filter-map (lambda (chunk)
                (let ((end (string-index chunk #\>)))
                  (and end
                       (substring chunk 0 end))))
              (string-split html #\<)))

(define (paints? tag)
  (any (lambda (property)
         (string-contains tag property)) painting-properties))

(define (painting-without-a-class html)
  "The elements of HTML that set a colour and name no class to re-point it."
  (filter (lambda (tag)
            (and (paints? tag)
                 (not (string-contains tag "class=\""))))
          (tags html)))

(define (classes-worn html)
  "Every class name the elements of HTML wear."
  (let loop
    ((rest html)
     (acc '()))
    (let ((at (string-contains rest "class=\"")))
      (if (not at)
          (reverse acc)
          (let* ((after (+ at
                           (string-length "class=\"")))
                 (end (string-index (substring rest after) #\")))
            (if (not end)
                (reverse acc)
                (loop (substring rest
                                 (+ after end 1))
                      (cons (substring rest after
                                       (+ after end)) acc))))))))

(define (unstyled-classes html)
  "The `pw-' classes of HTML that name no style in `mail-styles'."
  (let ((prefix "pw-"))
    (filter (lambda (class)
              (and (string-prefix? prefix class)
                   (not (assq (string->symbol (substring class
                                                         (string-length prefix)))
                              mail-styles))))
            (classes-worn html))))

(define dark-reach-suite
  (let ((ticket (lucidplan-new-ticket-html-template #:system-name "Lucidplan"
                 #:project-name "Pingwing"
                 #:ticket-human-id 12
                 #:ticket-title "Fix the SMTP retry"
                 #:ticket-type "bug"
                 #:priority 2
                 #:ticket-url "https://lucidplan/x/ticket/12"))
        (reset (password-reset-html-template #:system-name "WikiMusic"
                                             #:user "joe@x.y"
                                             #:reset-link "https://x/y"))
        (alert (system-alert-html-template #:system-name "X"
                                           #:alert-value "disk full")))
    (suite "what the dark override can reach"
           (test "nothing paints a colour without a class to re-point it"
                 (assert-empty #:name
                  "the ticket notice paints only through classes"
                  #:got (painting-without-a-class ticket))
                 (assert-empty #:name
                               "the reset mail paints only through classes"
                               #:got (painting-without-a-class reset))
                 (assert-empty #:name "the alert paints only through classes"
                               #:got (painting-without-a-class alert)))
           (test "every class a message wears is a style with a dark reading"
                 (assert-empty #:name
                  "every class of the ticket notice is a named style"
                  #:got (unstyled-classes ticket))
                 (assert-empty #:name
                  "every class of the reset mail is a named style"
                  #:got (unstyled-classes reset))
                 (assert-empty #:name
                               "every class of the alert is a named style"
                               #:got (unstyled-classes alert))))))

;;; ====== readability, in both readings of the palette ======

;; A colour is readable against the surface it is actually painted on, and in a
;; mail that surface is rarely flat.  The page is a gradient; the panel is
;; translucent over it; the inner pane is translucent over the panel.  So the
;; pair worth measuring is a text colour against the *composite* -- and against
;; the worst stop of the gradient, which is the one a reader who scrolls to the
;; bottom ends up on.  Expressing that here, next to the palette, is what keeps
;; the promise from decaying: a colour that is nudged for looks is measured
;; again the next time the suite runs, in whichever reading it was nudged.
;;
;; The floor is the WCAG one for body text, 4.5:1, and it is applied to every
;; pair rather than to the large ones only, because the tightest pair in this
;; palette is 13px small print.  A broken measurement would pass everything, so
;; the arithmetic is held to its two known answers as well: white on black is
;; the 21:1 a ratio can reach, and a colour on itself is 1:1.

(define contrast-floor
  4.5)

(define (components colour)
  "The (r g b . alpha) of COLOUR, in the two shapes the palette is written in:
`#rrggbb', and `rgba(r,g,b,a)' for anything translucent."
  (if (char=? (string-ref colour 0) #\#)
      (let ((value (string->number (substring colour 1) 16)))
        (list (quotient value 65536)
              (modulo (quotient value 256) 256)
              (modulo value 256) 1.0))
      (let ((channels (map string->number
                           (string-split (substring colour
                                                    (string-length "rgba(")
                                                    (1- (string-length colour)))
                                         #\,))))
        channels)))

(define (over foreground background)
  "FOREGROUND composited over BACKGROUND -- what a reader's eye adds up."
  (let ((alpha (list-ref foreground 3)))
    (append (map (lambda (channel
                           background-channel)
                   (+ (* channel alpha)
                      (* background-channel
                         (- 1 alpha))))
                 (list-head foreground 3)
                 (list-head background 3))
            '(1.0))))

(define (channel-luminance value)
  (let ((v (/ value 255.0)))
    (if (<= v 0.04045)
        (/ v 12.92)
        (expt (/ (+ v 0.055) 1.055) 2.4))))

(define (luminance colour)
  (+ (* 0.2126
        (channel-luminance (list-ref colour 0)))
     (* 0.7152
        (channel-luminance (list-ref colour 1)))
     (* 0.0722
        (channel-luminance (list-ref colour 2)))))

(define (contrast one other)
  "The WCAG contrast ratio between two opaque colours."
  (let ((a (luminance one))
        (b (luminance other)))
    (/ (+ (max a b) 0.05)
       (+ (min a b) 0.05))))

(define (colours-in text)
  "Every `#rrggbb' written in TEXT, in the order it is written."
  (reverse (fold-matches (make-regexp "#[0-9a-fA-F]{6}") text
                         '()
                         (lambda (match acc
                                   )
                           (cons (match:substring match) acc)))))

(define (surfaces scheme)
  "Every surface a text colour is painted on in SCHEME, by name.

The page is the gradient's own stops; the panel and the inner pane are the
composites of the translucent colours over it, in that order."
  (let* ((reading (palette scheme))
         (page (map components
                    (colours-in (color-of reading
                                          'bg-gradient))))
         (panel (map (lambda (stop)
                       (over (components (color-of reading
                                                   'panel)) stop)) page))
         (inner (map (lambda (surface)
                       (over (components (color-of reading
                                                   'inner)) surface)) panel)))
    (list (cons "the page" page)
          (cons "the panel" panel)
          (cons "the inner pane" inner)
          (cons "the button"
                (list (components (color-of reading
                                            'accent)))))))

;; Which text is set on which surface, and nothing more: the body text and the
;; small print of a body are read on the panel and on the pane inside it, the
;; small print alone also sits outside the panel where the footer is, and the one
;; thing ever read on the button is the button's label.  Measuring a pair that
;; cannot occur would only teach a reader to ignore a failure.
(define read-on
  '(("body text" "the page" "the panel" "the inner pane")
    ("headings" "the panel" "the inner pane")
    ("small print" "the page" "the panel" "the inner pane")
    ("the button's label" "the button")))

(define (text-colour-of scheme role)
  "The palette entry for ROLE -- a phrase from `read-on' -- in SCHEME."
  (color-of (palette scheme)
            (cond
              ((string=? role "body text")
               'ink)
              ((string=? role "headings")
               'heading)
              ((string=? role "small print")
               'muted)
              (else 'accent-ink))))

(define (below-floor scheme)
  "The text colours of SCHEME that fall under the floor, and where."
  (let ((all (surfaces scheme)))
    (append-map (lambda (role)
                  (let ((text (components (text-colour-of scheme
                                                          (car role)))))
                    (filter-map (lambda (name)
                                  (let ((worst (apply min
                                                      (map (lambda (background)
                                                             (contrast text
                                                              background))
                                                           (assoc-ref all name)))))
                                    (and (< worst contrast-floor)
                                         (format #f
                                          "~a in ~a: ~,2f:1 on ~a, under ~a:1"
                                          (car role)
                                          scheme
                                          worst
                                          name
                                          contrast-floor))))
                                (cdr role)))) read-on)))

;; The list above says which colours are measured, and a list is only as good as
;; what keeps it complete: a new text style could ship a colour no role here ever
;; measured, and the floor would pass by simply not looking at it.  So the
;; colours a message actually carries are read back out of it -- the inline ones
;; and the head's override both, since both are in the same document -- and every
;; one of them has to be a colour the floor was applied to.
(define (measured-text-colours)
  "Every colour the readability checks above put a floor under."
  (delete-duplicates (append-map (lambda (scheme)
                                   (map (lambda (role)
                                          (text-colour-of scheme
                                                          (car role))) read-on))
                                 '(light dark)) equal?))

(define (declared-text-colours html)
  "Every colour HTML sets through a `color' declaration -- the text colours a
message ships.  A `border-color' or a `background-color' is not one of them, so
the pattern only matches a `color' that ends a word."
  (let ((pattern (make-regexp "(^|[^-a-zA-Z])color: *([^;!]+)")))
    (map (lambda (found)
           (string-trim-right (match:substring found 2)))
         (list-matches pattern html))))

(define (unmeasured-text-colours html)
  "The text colours of HTML that no floor was measured for."
  (let ((measured (measured-text-colours)))
    (delete-duplicates (filter (lambda (colour)
                                 (not (member colour measured)))
                               (declared-text-colours html)) equal?)))

(define readability-suite
  (let ((ticket (lucidplan-new-ticket-html-template #:system-name "Lucidplan"
                 #:project-name "Pingwing"
                 #:ticket-human-id 12
                 #:ticket-title "Fix the SMTP retry"
                 #:ticket-type "bug"
                 #:priority 2
                 #:ticket-url "https://lucidplan/x/ticket/12"))
        (reset (password-reset-html-template #:system-name "WikiMusic"
                                             #:user "joe@x.y"
                                             #:reset-link "https://x/y"))
        (alert (system-alert-html-template #:system-name "X"
                                           #:alert-value "disk full")))
    (suite "readability, in both readings of the palette"
           (test "the measurement is the one WCAG defines"
                 (assert-approximate #:name
                  "white on black is the 21:1 a ratio can reach"
                  #:expect 21.0
                  #:epsilon 0.01
                  #:got (contrast (components "#ffffff")
                                  (components "#000000")))
                 (assert-approximate #:name "a colour on itself is 1:1"
                                     #:expect 1.0
                                     #:epsilon 0.001
                                     #:got (contrast (components "#4a5259")
                                                     (components "#4a5259"))))
           (test "every colour clears the floor on every surface it is set on"
            (assert-empty #:name
             "the light reading clears the floor everywhere it is read"
             #:got (below-floor 'light))
            (assert-empty #:name
             "the dark reading clears the floor everywhere it is read"
             #:got (below-floor 'dark)))
           (test "no message ships a text colour the floor was not applied to"
            (assert-empty #:name
             "the ticket notice ships only measured text colours"
             #:got (unmeasured-text-colours ticket))
            (assert-empty #:name
                          "the reset mail ships only measured text colours"
                          #:got (unmeasured-text-colours reset))
            (assert-empty #:name "the alert ships only measured text colours"
                          #:got (unmeasured-text-colours alert))))))

;;; ====== the look ======

(define styling-suite
  (let ((head (mail-head-style)))
    (suite "the fonts and the glass"
           (test "the faces are declared"
                 (assert-contains #:name "Work Sans is declared"
                                  #:expect head
                                  #:got "Work Sans")
                 (assert-contains #:name "Source Serif 4 is declared"
                                  #:expect head
                                  #:got "Source Serif 4")
                 (assert-contains #:name "JuliaMono is declared"
                                  #:expect head
                                  #:got "JuliaMono"))
           (test "both colour schemes are offered"
                 (assert-contains #:name "a dark theme is offered"
                                  #:expect head
                                  #:got "prefers-color-scheme"))
           (test "the panel declares a frost blur"
                 (assert-contains #:name
                  "the panel is frosted, not merely translucent"
                  #:expect (password-reset-html-template #:system-name "X"
                                                         #:user "u@x.y"
                                                         #:reset-link
                                                         "https://x/y")
                  #:got "backdrop-filter")))))
(define (spec)
  (veritas-run password-reset-suite
               system-alert-suite
               new-ticket-suite
               document-suite
               markup-suite
               dark-reach-suite
               readability-suite
               styling-suite))
