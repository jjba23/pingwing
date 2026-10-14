;;; pingwing -- the free and open Lisp-powered notification nexus

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; pingwing is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; pingwing is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU Affero General Public License for more details.

;; You should have received a copy of the GNU Affero General Public License
;; along with pingwing.  If not, see <https://www.gnu.org/licenses/>.

;;; Mail is not the web.  The one rule this module is written around is that a
;;; mail client is free to throw away everything in the document's <head>: no
;;; stylesheet, no web font, no media query.  So every colour, size and shape
;;; that a message cannot do without is written straight onto the element that
;;; wears it, by these helpers, and the <head> only carries the two things that
;;; cannot be said inline -- the @font-face declarations and a dark-mode
;;; override -- as a courtesy for the clients that do read them.  A message
;;; that loses the whole <head> still reads as the same message; it just falls
;;; back to Lucida or the system sans and to the light palette, which is what
;;; the rest of these declarations are already chosen to match.

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
                             mail-mono-stack
                             mail-head-style
                             mail-light
                             mail-dark
                             color-of))

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

;; The one function every template reaches for: turn an alist of CSS
;; declarations into the single string a `style` attribute holds.  A pair
;; whose value is #f or "" is dropped, which is what lets a caller write an
;; optional declaration without branching around it.
(define (mk-style xs)
  (string-join (filter-map (lambda (x)
                             (let ((key (car x))
                                   (value (cdr x)))
                               (and value
                                    (not (equal? value ""))
                                    (format #f "~a: ~a;" key value)))) xs) " "))

;; The type faces the happy path asks for.  The first name in each stack is
;; the webfont the head style declares; the rest are what a mail client that
;; refused the font falls back to, chosen to sit on the same footing -- Lucida
;; Sans on the desktop, and the system sans elsewhere.  The monospaced stack
;; is the same bargain with Intel One Mono and Lucida Sans Typewriter.
(define mail-sans-stack
  "'Lucida Sans','Lucida Grande','Lucida Sans Unicode','DejaVu Sans',Verdana,'Segoe UI',Roboto,sans-serif")

(define mail-mono-stack
  "'Intel One Mono','Lucida Sans Typewriter','DejaVu Sans Mono','Liberation Mono',Menlo,Consolas,'Courier New',monospace")

;; The one palette, in the everforest greens the hygguile surfaces are tinted
;; with, so a pingwing mail reads as a member of the same family as the sites
;; that send it.  Both readings are here rather than in a stylesheet because
;; the light one is what the inline styles use and the dark one exists only in
;; the head, for the clients that honour it.
(define mail-light
  '((bg . "#e7e4dc")
    (bg-gradient . "linear-gradient(160deg,#fbfaf6 0%,#eeece6 45%,#dedbd3 100%)")
    (ink . "#4a5259")
    (heading . "#2b3339")
    (muted . "#7d8880")
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
    (muted . "#9aa79a")
    (panel . "rgba(51,59,64,0.72)")
    (panel-border . "rgba(211,198,170,0.22)")
    (panel-shadow . "0 18px 44px rgba(0,0,0,0.38)")
    (inner . "rgba(211,198,170,0.08)")
    (inner-border . "rgba(211,198,170,0.18)")
    (accent . "#a7c080")
    (accent-ink . "#2b3339")
    (rule . "rgba(211,198,170,0.22)")))

(define (color-of palette key)
  "The colour KEY names in PALETTE, or #f when it names none."
  (assq-ref palette key))

;; The @font-face declarations: the Lucida faces the hygguile sites serve from
;; jointhefreeworld's own asset host, plus Intel One Mono from Google Fonts.
;; They are the two families the inline styles ask for first; a client that
;; loads neither simply reaches past them to its own fonts.
(define mail-font-faces
  (string-append
   "@import url('https://fonts.googleapis.com/css2?family=Intel+One+Mono:ital,wght@0,300..700;1,300..700&display=swap');
"
   "@font-face{font-family:'Lucida Sans';font-style:normal;font-weight:400;font-display:swap;src:url('https://jointhefreeworld.org/static-assets/fonts/LSANS.woff') format('woff');}
"
   "@font-face{font-family:'Lucida Sans';font-style:italic;font-weight:400;font-display:swap;src:url('https://jointhefreeworld.org/static-assets/fonts/LSANSI.woff') format('woff');}
"
   "@font-face{font-family:'Lucida Sans';font-style:normal;font-weight:600;font-display:swap;src:url('https://jointhefreeworld.org/static-assets/fonts/LSANSD.woff') format('woff');}
"
   "@font-face{font-family:'Lucida Sans';font-style:italic;font-weight:600;font-display:swap;src:url('https://jointhefreeworld.org/static-assets/fonts/LSANSDI.woff') format('woff');}
"
   "@font-face{font-family:'Lucida Sans Typewriter';font-style:normal;font-weight:400;font-display:swap;src:url('https://jointhefreeworld.org/static-assets/fonts/LTYPE.woff') format('woff');}
"
   "@font-face{font-family:'Lucida Sans Typewriter';font-style:oblique;font-weight:400;font-display:swap;src:url('https://jointhefreeworld.org/static-assets/fonts/LTYPEO.woff') format('woff');}
"
   "@font-face{font-family:'Lucida Sans Typewriter';font-style:normal;font-weight:700;font-display:swap;src:url('https://jointhefreeworld.org/static-assets/fonts/LTYPEB.woff') format('woff');}
"))

;; The frosted glass itself, as much of it as a mail can hold.  `backdrop-filter'
;; is not something a mail client will do, so the glass is faked the way it has
;; always been faked where blur is not available: a translucent panel over a
;; soft gradient, a hairline border and a long, low shadow to lift it off the
;; page.  Every one of those is inline too (see the templates); this rule only
;; re-points the classes at the dark palette when the reader's client says so,
;; which is the one thing that genuinely cannot be written inline.
(define (dark-overrides)
  (format #f
   "@media (prefers-color-scheme: dark) {
  .pw-body { background-color: ~a !important; background-image: ~a !important; color: ~a !important; }
  .pw-panel { background-color: ~a !important; border-color: ~a !important; box-shadow: ~a !important; }
  .pw-heading { color: ~a !important; }
  .pw-text { color: ~a !important; }
  .pw-muted { color: ~a !important; }
  .pw-inner { background-color: ~a !important; border-color: ~a !important; }
  .pw-rule { border-color: ~a !important; }
  .pw-button { background-color: ~a !important; color: ~a !important; }
  .pw-mono { color: ~a !important; }
}
"
   (color-of mail-dark
             'bg)
   (color-of mail-dark
             'bg-gradient)
   (color-of mail-dark
             'ink)
   (color-of mail-dark
             'panel)
   (color-of mail-dark
             'panel-border)
   (color-of mail-dark
             'panel-shadow)
   (color-of mail-dark
             'heading)
   (color-of mail-dark
             'ink)
   (color-of mail-dark
             'muted)
   (color-of mail-dark
             'inner)
   (color-of mail-dark
             'inner-border)
   (color-of mail-dark
             'rule)
   (color-of mail-dark
             'accent)
   (color-of mail-dark
             'accent-ink)
   (color-of mail-dark
             'accent)))

;; What a message's <head> holds: the fonts, then the dark-mode polish.  Kept
;; deliberately tiny, because everything a reader has to see is inline.
(define (mail-head-style)
  (string-append mail-font-faces "\n"
                 (dark-overrides)))
