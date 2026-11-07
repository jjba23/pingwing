;; pingwing - the free and open Lisp-powered notification nexus
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Mail is not the web.  The one rule this module is written around is that a
;;; mail client is free to throw away everything in the document's <head>: no
;;; stylesheet, no web font, no media query.  So every colour, size and shape
;;; that a message cannot do without is written straight onto the element that
;;; wears it, and the <head> only carries the two things that cannot be said
;;; inline -- the @font-face declarations and a dark-mode override -- as a
;;; courtesy for the clients that do read them.  A message that loses the whole
;;; <head> still reads as the same message; it just falls back to the system
;;; sans and to the light palette, which is what the rest of these
;;; declarations are already chosen to match.
;;;
;;; The dark override is the one place a colour has to be said twice -- the
;;; inline style is light, and the reader's client may ask for dark -- so it is
;;; not written twice by hand.  Every element that paints carries a class, and
;;; every class is an entry in `mail-styles': one list of declarations, read
;;; once in the light palette for the inline style and once in the dark palette
;;; for the override, which keeps only the declarations that actually differ.
;;; A colour is therefore added in one place and reaches both readings, and an
;;; element that paints without wearing a class cannot be re-pointed at all --
;;; which is what `test/veritas/unit/templates-spec.scm' asserts over every
;;; template.

(define-module (pingwing css)
  #:use-module (ice-9 textual-ports)
  #:use-module (ice-9 time)
  #:use-module (ice-9 format)
  #:use-module (ice-9 string-fun)
  #:use-module (ice-9 iconv)
  #:use-module (srfi srfi-1)
  #:export (mk-kv-conf-lines mk-css-conf-lines
                             mk-style
                             mail-sans-stack
                             mail-serif-stack
                             mail-mono-stack
                             mail-head-style
                             mail-light
                             mail-dark
                             palette
                             colour
                             border
                             color-of
                             class-name
                             style-of
                             mail-styles))

;; Create a CSS configuration from PAIRS, a selector to values alist.
(define* (mk-kv-conf-lines pairs
                           #:key (template "~a=~a\n"))
  (with-output-to-string (lambda ()
                           (for-each (lambda (x)
                                       (display (format #f template
                                                        (car x)
                                                        (cdr x)))) pairs))))

(define* (mk-css-conf-lines pairs)
  (with-output-to-string (lambda ()
                           (for-each (lambda (x)
                                       (display (format #f "~a {\n"
                                                        (car x)))
                                       (display (mk-kv-conf-lines (cdr x)
                                                                  #:template
                                                                  "  ~a: ~a;\n"))
                                       (display "}\n\n")) pairs))))

;;; ====== the two readings of the palette ======

;; The one palette, in the everforest greens the hygguile surfaces are tinted
;; with, so a pingwing mail reads as a member of the same family as the sites
;; that send it.  Both readings are here because both are needed: the light one
;; is what the inline styles are written with, and the dark one is what the
;; head's media query re-points them at.
;;
;; `muted' is the small print -- the footer, the hints, the labels beside a
;; fact -- and it is chosen to clear 4.5:1 against the darkest surface it is
;; ever set on in its own scheme, rather than to look quiet at the expense of
;; being readable.  Which surface that is differs between the two readings, and
;; that is the whole reason the check is mechanical: in the light one the small
;; print that sits *outside* the panel -- the footer, over the gradient's own
;; last stop -- is the tightest pair, while in the dark one it is the fact
;; labels inside the inner pane, where a translucent pane over a translucent
;; panel leaves the least room.  Both are measured, in both readings, by the
;; suite rather than trusted here.
(define mail-light
  '((bg . "#e7e4dc")
    (bg-gradient . "linear-gradient(160deg,#fbfaf6 0%,#eeece6 45%,#e6e3db 100%)")
    (ink . "#4a5259")
    (heading . "#2b3339")
    (muted . "#5c655f")
    (panel . "rgba(252,251,247,0.72)")
    (panel-border . "rgba(120,113,108,0.26)")
    (panel-shadow . "0 18px 44px rgba(43,51,57,0.14)")
    (inner . "rgba(120,113,108,0.08)")
    (inner-border . "rgba(120,113,108,0.18)")
    (accent . "#a7c080")
    (accent-ink . "#2b3339")
    (rule . "rgba(120,113,108,0.28)")))

(define mail-dark
  '((bg . "#232a2e")
    (bg-gradient . "linear-gradient(160deg,#333b40 0%,#2b3339 55%,#232a2e 100%)")
    (ink . "#d3c6aa")
    (heading . "#e6ddc4")
    (muted . "#adb9ab")
    (panel . "rgba(51,59,64,0.72)")
    (panel-border . "rgba(211,198,170,0.22)")
    (panel-shadow . "0 18px 44px rgba(0,0,0,0.38)")
    (inner . "rgba(211,198,170,0.08)")
    (inner-border . "rgba(211,198,170,0.18)")
    (accent . "#a7c080")
    (accent-ink . "#2b3339")
    (rule . "rgba(211,198,170,0.22)")))

(define (palette scheme)
  "The palette SCHEME names -- 'light or 'dark."
  (if (eq? scheme
           'dark) mail-dark mail-light))

(define (color-of palette key)
  "The colour KEY names in PALETTE, or #f when it names none."
  (assq-ref palette key))

;;; ====== a declaration's value, and the scheme it is written for ======

;; A declaration's value is usually a string that is the same in both schemes
;; ("font-size" . "13px").  Where it is a colour -- or anything built out of
;; one, a hairline border, a gradient -- it is one of the two procedures below,
;; which read the palette of whichever scheme is being written out.  That is
;; what lets a single declaration list be written twice, once inline and once
;; into the dark override, without the two ever being able to disagree.
(define (colour key)
  "A declaration value: the palette's KEY, in the scheme being written."
  (lambda (scheme)
    (color-of (palette scheme) key)))

(define* (border key
                 #:key (width "1px")
                 (style "solid"))
  "A declaration value: a WIDTH and STYLE border in the palette's KEY."
  (lambda (scheme)
    (format #f "~a ~a ~a" width style
            (color-of (palette scheme) key))))

(define (written-value value scheme)
  "VALUE as it is written in SCHEME -- a palette reading, or VALUE itself."
  (if (procedure? value)
      (value scheme) value))

;; The one function every template reaches for: turn an alist of CSS
;; declarations into the single string a `style` attribute holds.  A pair
;; whose value is #f or "" is dropped, which is what lets a caller write an
;; optional declaration without branching around it.
(define* (mk-style decls
                   #:key (scheme 'light))
  (string-join (filter-map (lambda (x)
                             (let ((key (car x))
                                   (value (written-value (cdr x) scheme)))
                               (and value
                                    (not (equal? value ""))
                                    (format #f "~a: ~a;" key value)))) decls)
               " "))

;; The type faces the happy path asks for.  The first name in each stack is
;; the webfont the head style declares; the rest are what a mail client that
;; refused the font falls back to, chosen to sit on the same footing -- the
;; reader's own sans, serif and monospace, the last keeping its columns.  All
;; three families are libre (SIL Open Font License 1.1) and served from one host
;; of ours.
(define mail-sans-stack
  "'Work Sans','Segoe UI',Roboto,'Helvetica Neue',Arial,'Noto Sans',sans-serif")

(define mail-serif-stack
  "'Source Serif 4','Source Serif Pro',Georgia,'Times New Roman',serif")

(define mail-mono-stack
  "'JuliaMono','DejaVu Sans Mono','Liberation Mono',Menlo,Consolas,'Courier New',monospace")

;;; ====== every style a message wears, in one table ======

;; The name of each entry is also the class the element wears -- `heading' is
;; `pw-heading' -- which is what the head's dark override selects on.  An
;; element that paints has to be in here: a colour written anywhere else is a
;; colour the dark palette cannot reach, and the test suite refuses one.
(define mail-styles
  `((body ("margin" . "0")
          ("padding" . "0")
          ("width" . "100%")
          ("background-color" unquote
           (colour 'bg))
          ("background-image" unquote
           (colour 'bg-gradient))
          ("font-family" unquote mail-sans-stack)
          ("font-size" . "16px")
          ("line-height" . "1.6")
          ("color" unquote
           (colour 'ink))
          ("-webkit-font-smoothing" . "antialiased"))
    (panel ("width" . "100%")
           ("max-width" . "600px")
           ("border-collapse" . "separate")
           ("background-color" unquote
            (colour 'panel))
           ("border" unquote
            (border 'panel-border))
           ("border-radius" . "24px")
           ("box-shadow" unquote
            (colour 'panel-shadow))
           ("backdrop-filter" . "blur(16px)")
           ("-webkit-backdrop-filter" . "blur(16px)")
           ("overflow" . "hidden"))
    ;; The hairline of colour along the top of the glass: the one place the
    ;; mail gets to show the washes the web surfaces drift, without asking the
    ;; reader's client for a blur it will not give.  It is the same hairline in
    ;; both schemes, so it is here for completeness rather than for a rule.
    (accent ("height" . "6px")
            ("line-height" . "0")
            ("font-size" . "0")
            ("background-image" . "linear-gradient(90deg,#a7c080,#e67e80,#dbbc7f,#7fbbb3)"))
    (inner ("background-color" unquote
            (colour 'inner))
           ("border" unquote
            (border 'inner-border))
           ("border-radius" . "16px")
           ("padding" . "18px 20px")
           ("margin" . "22px 0"))
    (heading ("color" unquote
              (colour 'heading))
             ("font-family" unquote mail-sans-stack)
             ("font-size" . "23px")
             ("font-weight" . "600")
             ("line-height" . "1.35")
             ("margin" . "0 0 6px"))
    (text ("color" unquote
           (colour 'ink))
          ("font-family" unquote mail-sans-stack)
          ("font-size" . "16px")
          ("line-height" . "1.65")
          ("margin" . "14px 0"))
    (muted ("color" unquote
            (colour 'muted))
           ("font-family" unquote mail-sans-stack)
           ("font-size" . "13px")
           ("line-height" . "1.55")
           ("margin" . "0 0 6px"))
    (mono ("color" unquote
           (colour 'heading))
          ("font-family" unquote mail-mono-stack)
          ("font-size" . "13px")
          ("word-break" . "break-all"))
    ;; The two columns of a fact row, and the two places a message links out.
    ;; They carry no furniture of their own, only a colour, which is exactly
    ;; why they are easy to forget here -- and why forgetting them is visible.
    (fact-label ("color" unquote
                 (colour 'muted))
                ("font-family" unquote mail-sans-stack)
                ("font-size" . "13px")
                ("padding" . "4px 12px 4px 0")
                ("vertical-align" . "top"))
    (fact-value ("color" unquote
                 (colour 'heading))
                ("font-family" unquote mail-sans-stack)
                ("font-size" . "14px")
                ("padding" . "4px 0")
                ("text-align" . "right")
                ("vertical-align" . "top"))
    (link ("color" unquote
           (colour 'heading))
          ("text-decoration" . "underline"))
    (footer-link ("color" unquote
                  (colour 'muted))
                 ("text-decoration" . "underline"))
    ;; The alert block a system-alert mail carries: monospaced and wrapped, so
    ;; a stack trace or a list of numbers keeps the shape it was written in.
    (alert ("color" unquote
            (colour 'heading))
           ("font-family" unquote mail-mono-stack)
           ("font-size" . "13px")
           ("white-space" . "pre-wrap")
           ("word-break" . "break-word"))
    (rule ("border-top" unquote
           (border 'rule))
          ("margin" . "24px 0")
          ("font-size" . "0")
          ("line-height" . "0"))
    (button ("background-color" unquote
             (colour 'accent))
            ("border-radius" . "999px")
            ("padding" . "13px 26px"))
    ;; The ink on the button never changes with the scheme: the button is the
    ;; same green in both, and its label is dark on it either way.
    (button-ink ("color" unquote
                 (colour 'accent-ink))
                ("font-family" unquote mail-sans-stack)
                ("font-size" . "16px")
                ("font-weight" . "600")
                ("text-decoration" . "none")
                ("display" . "inline-block"))))

(define (class-name name)
  "The class an element wears for the style NAME."
  (format #f "pw-~a" name))

(define* (style-of name
                   #:key (scheme 'light))
  "The declarations of the style NAME as one `style' attribute value.

Read in SCHEME, so the same name yields the inline style of a message and the
overrides of its dark reading."
  (mk-style (assq-ref mail-styles name)
            #:scheme scheme))

;; The @font-face declarations: Work Sans for the prose, Source Serif 4 for the
;; serif and JuliaMono for the monospaced runs, the three families the inline
;; styles can ask for.  All are libre (SIL Open Font License 1.1) and all are
;; served from the project's own asset host rather than from a font service, so a
;; message asks no third party for its type; a client that loads none of them
;; simply reaches past them to its own fonts.  The three are variable fonts, so
;; one file per style carries the whole weight axis; JuliaMono ships static
;; weights, hence the pair split at 600.
(define mail-font-faces
  (string-append
   "@font-face{font-family:'Work Sans';font-style:normal;font-weight:100 900;font-display:swap;src:url('https://jointhefreeworld.org/static-assets/fonts/work-sans-normal-latin.woff2') format('woff2');}
"
   "@font-face{font-family:'Work Sans';font-style:italic;font-weight:100 900;font-display:swap;src:url('https://jointhefreeworld.org/static-assets/fonts/work-sans-italic-latin.woff2') format('woff2');}
"
   "@font-face{font-family:'Source Serif 4';font-style:normal;font-weight:200 900;font-display:swap;src:url('https://jointhefreeworld.org/static-assets/fonts/source-serif-4-normal-latin.woff2') format('woff2');}
"
   "@font-face{font-family:'Source Serif 4';font-style:italic;font-weight:200 900;font-display:swap;src:url('https://jointhefreeworld.org/static-assets/fonts/source-serif-4-italic-latin.woff2') format('woff2');}
"
   "@font-face{font-family:'JuliaMono';font-style:normal;font-weight:300 500;font-display:swap;src:url('https://jointhefreeworld.org/static-assets/fonts/juliamono-normal-latin.woff2') format('woff2');}
"
   "@font-face{font-family:'JuliaMono';font-style:normal;font-weight:600 900;font-display:swap;src:url('https://jointhefreeworld.org/static-assets/fonts/juliamono-bold-latin.woff2') format('woff2');}
"))

;;; ====== the dark override, generated from that table ======

;; The frosted glass itself, as much of it as a mail can hold.
;; `backdrop-filter' is not something a mail client will do, so the glass is
;; faked the way it has always been faked where blur is not available: a
;; translucent panel over a soft gradient, a hairline border and a long, low
;; shadow to lift it off the page.
;;
;; Only the declarations whose two readings actually differ are emitted, so a
;; style that is the same in both schemes (the accent hairline, the button's
;; ink) costs no rule -- and a style whose reading changes cannot be left out of
;; the override, because nothing here is written by hand.
(define (changed-declarations decls)
  (filter (lambda (declaration)
            (let ((light (written-value (cdr declaration)
                                        'light))
                  (dark (written-value (cdr declaration)
                                       'dark)))
              (and dark
                   (not (equal? light dark))))) decls))

(define (dark-rules)
  (filter-map (lambda (entry)
                (let* ((name (car entry))
                       (changed (changed-declarations (cdr entry))))
                  (and (pair? changed)
                       (format #f "  .~a { ~a }"
                               (class-name name)
                               (string-join (map (lambda (declaration)
                                                   (format #f
                                                    "~a: ~a !important;"
                                                    (car declaration)
                                                    (written-value (cdr
                                                                    declaration)
                                                                   'dark)))
                                                 changed) " "))))) mail-styles))

(define (dark-overrides)
  "The head's one media query: every style whose dark reading differs.

`!important' is what it takes, because the same declarations are inline on the
element and an inline style outranks a rule of the page."
  (format #f "@media (prefers-color-scheme: dark) {
~a
}
"
          (string-join (dark-rules) "\n")))

;; What a message's <head> holds: the fonts, then the dark-mode polish.  Kept
;; deliberately tiny, because everything a reader has to see is inline.
(define (mail-head-style)
  (string-append mail-font-faces "\n"
                 (dark-overrides)))
