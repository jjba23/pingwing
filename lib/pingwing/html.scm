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

;;; The furniture every pingwing message is built from: the document head, the
;;; frosted-glass panel, the accent hairline, the call-to-action button and the
;;; footer.  A template supplies the words and picks the bits it wants; the
;;; look -- a translucent pane over a soft gradient, lifted by a low shadow,
;;; with the everforest greens as the one accent -- lives here so that all the
;;; messages agree, and every one of these nodes carries its style inline (see
;;; `(pingwing css)' for why).

(define-module (pingwing html)
  #:use-module (ice-9 textual-ports)
  #:use-module (ice-9 time)
  #:use-module (ice-9 format)
  #:use-module (ice-9 string-fun)
  #:use-module (srfi srfi-1)
  #:use-module (pingwing css)
  #:use-module (ice-9 iconv)
  #:export (meta-charset meta-ie
                         meta-responsive
                         meta-color-scheme
                         meta-supported-color-schemes
                         mail-head
                         mail-heading-style
                         mail-text-style
                         mail-muted-style
                         mail-mono-style
                         mail-footer
                         mail-document
                         mail-panel
                         mail-accent
                         mail-button
                         mail-rule
                         mail-inner
                         mail-link
                         mail-facts
                         mail-mono))

;; `sxml->xml' writes an element that has no children at all as a
;; self-closing tag -- `<div ... />' -- which is XML, not HTML.  An HTML
;; parser reads that as an *opening* tag and makes everything written after it
;; its children, so a panel that did it would swallow the whole message body
;; and the mail would arrive as an empty card.  Any element below that may end
;; up with nothing to hold therefore carries this: `as-children' is the one
;; that leaves nothing out, and the elements whose content a caller supplies
;; are passed through it so that no caller can hand in a list that empties
;; them.
(define no-content
  "")

;; CHILDREN with a placeholder in it when it has none, so that an element built
;; from a caller's list is never written self-closing.  `(or children ...)'
;; would not do: the empty list is not false in Scheme, so it would slip
;; through and the element would be written as `<div ... />' anyway.
(define (as-children children)
  (if (null? children)
      (list no-content) children))

(define-public meta-charset
  `(meta (@ (http-equiv . Content-Type)
            (content . "text/html; charset=utf-8"))))

(define-public meta-ie
  `(meta (@ (http-equiv . X-UA-Compatible)
            (content . "IE=edge"))))

(define-public meta-responsive
  `(meta (@ (name . viewport)
            (content . "width=device-width,initial-scale=1.0"))))

(define-public meta-color-scheme
  `(meta (@ (name . color-scheme)
            (content . "light dark"))))

(define-public meta-supported-color-schemes
  `(meta (@ (name . supported-color-schemes)
            (content . "light dark"))))

;; The three text styles a template reaches for, all keyed to the light
;; palette (the head's dark override re-points the classes at the dark one).
(define (mail-heading-style)
  (mk-style `(("color" unquote
               (color-of mail-light
                         'heading))
              ("font-family" unquote mail-sans-stack)
              ("font-size" . "23px")
              ("font-weight" . "600")
              ("line-height" . "1.35")
              ("margin" . "0 0 6px"))))

(define (mail-text-style)
  (mk-style `(("color" unquote
               (color-of mail-light
                         'ink))
              ("font-family" unquote mail-sans-stack)
              ("font-size" . "16px")
              ("line-height" . "1.65")
              ("margin" . "14px 0"))))

(define (mail-muted-style)
  (mk-style `(("color" unquote
               (color-of mail-light
                         'muted))
              ("font-family" unquote mail-sans-stack)
              ("font-size" . "13px")
              ("line-height" . "1.55")
              ("margin" . "0 0 6px"))))

(define (mail-mono-style)
  (mk-style `(("color" unquote
               (color-of mail-light
                         'heading))
              ("font-family" unquote mail-mono-stack)
              ("font-size" . "13px")
              ("word-break" . "break-all"))))

(define* (mail-head #:key title)
  `(head ,meta-charset
         ,meta-ie
         ,meta-responsive
         ,meta-color-scheme
         ,meta-supported-color-schemes
         (title ,title)
         (style ,(mail-head-style))))

;; The hairline of colour along the top of the glass: the one place the mail
;; gets to show the washes the web surfaces drift, without asking the reader's
;; client for a blur it will not give.
(define (mail-accent)
  `(div (@ (class . "pw-accent")
           (style ,(mk-style `(("height" . "6px") ("line-height" . "0")
                               ("font-size" . "0")
                               ("background-image" . "linear-gradient(90deg,#a7c080,#e67e80,#dbbc7f,#7fbbb3)")))))
        ,no-content))

;; The panel: what every message sits in.  `backdrop-filter' is declared for
;; the clients that would honour it, but the visible glass is the translucent
;; tint over the gradient behind it, so a client that drops the filter still
;; shows a pane.
(define* (mail-panel content
                     #:key (accent #t))
  `(table (@ (role . "presentation")
             (width . "600")
             (cellpadding . "0")
             (cellspacing . "0")
             (border . "0")
             (class . "pw-panel")
             (style ,(mk-style `(("width" . "100%") ("max-width" . "600px")
                                 ("border-collapse" . "separate")
                                 ("background-color" unquote
                                  (color-of mail-light
                                            'panel))
                                 ("border" unquote
                                  (format #f "1px solid ~a"
                                          (color-of mail-light
                                                    'panel-border)))
                                 ("border-radius" . "24px")
                                 ("box-shadow" unquote
                                  (color-of mail-light
                                            'panel-shadow))
                                 ("backdrop-filter" . "blur(16px)")
                                 ("-webkit-backdrop-filter" . "blur(16px)")
                                 ("overflow" . "hidden")))))
          (tr (td (@ (style "padding:0;"))
                  ,@(if accent
                        (list (mail-accent))
                        '())
                  (div (@ (style "padding:38px 34px;"))
                       ,@(as-children content))))))

(define* (mail-button #:key href label)
  `(table (@ (role . "presentation")
             (cellpadding . "0")
             (cellspacing . "0")
             (border . "0")
             (style "border-collapse:separate;margin:24px 0;"))
          (tr (td (@ (class . "pw-button")
                     (style ,(mk-style `(("background-color" unquote
                                          (color-of mail-light
                                                    'accent))
                                         ("border-radius" . "999px")
                                         ("padding" . "13px 26px")))))
                  (a (@ (href ,href)
                        (style ,(mk-style `(("color" unquote
                                             (color-of mail-light
                                                       'accent-ink))
                                            ("font-family" unquote
                                             mail-sans-stack)
                                            ("font-size" . "16px")
                                            ("font-weight" . "600")
                                            ("text-decoration" . "none")
                                            ("display" . "inline-block")))))
                     ,label)))))

(define (mail-rule)
  `(div (@ (class . "pw-rule")
           (style ,(mk-style `(("border-top" unquote
                                (format #f "1px solid ~a"
                                        (color-of mail-light
                                                  'rule)))
                               ("margin" . "24px 0")
                               ("font-size" . "0")
                               ("line-height" . "0")))))
        ,no-content))

;; A second, lighter pane inside the first, for the few facts a message wants
;; set apart -- the ticket it is about, the account a reset concerns.
(define* (mail-inner content)
  `(div (@ (class . "pw-inner")
           (style ,(mk-style `(("background-color" unquote
                                (color-of mail-light
                                          'inner))
                               ("border" unquote
                                (format #f "1px solid ~a"
                                        (color-of mail-light
                                                  'inner-border)))
                               ("border-radius" . "16px")
                               ("padding" . "18px 20px")
                               ("margin" . "22px 0")))))
        ,@(as-children content)))

;; A two-column list of label/value facts, set in a small pane: what a reset
;; is about or what a ticket says, at a glance.  A row whose value is #f is
;; left out, so a template can pass an optional detail without branching.
(define (fact-row row)
  (let ((label (car row))
        (value (cdr row)))
    (and value
         (not (equal? value ""))
         `(tr (td (@ (style ,(mk-style `(("color" unquote
                                          (color-of mail-light
                                                    'muted))
                                         ("font-family" unquote
                                          mail-sans-stack)
                                         ("font-size" . "13px")
                                         ("padding" . "4px 12px 4px 0")
                                         ("vertical-align" . "top")))))
                  ,label)
              (td (@ (style ,(mk-style `(("color" unquote
                                          (color-of mail-light
                                                    'heading))
                                         ("font-family" unquote
                                          mail-sans-stack)
                                         ("font-size" . "14px")
                                         ("padding" . "4px 0")
                                         ("text-align" . "right")
                                         ("vertical-align" . "top")))))
                  ,value)))))

(define (mail-facts rows)
  `(table (@ (role . "presentation")
             (width . "100%")
             (cellpadding . "0")
             (cellspacing . "0")
             (border . "0")
             (style "border-collapse:collapse;"))
          ,@(as-children (filter-map fact-row rows))))

;; Wrap VALUE in the monospaced, slightly accented voice the templates use
;; for the facts a reader may want to copy: an account name, a ticket number,
;; a link that has to survive a mail client's own link-mangling.
(define* (mail-mono value
                    #:key (style (mail-mono-style)))
  `(span (@ (class . "pw-mono")
            (style ,style))
         ,value))

(define* (mail-link #:key href label)
  `(a (@ (href ,href)
         (style ,(mk-style `(("color" unquote
                              (color-of mail-light
                                        'heading))
                             ("text-decoration" . "underline")))))
      ,label))

(define-public mail-footer
  `(table (@ (role . "presentation")
             (width . "100%")
             (cellpadding . "0")
             (cellspacing . "0")
             (border . "0")
             (style "border-collapse:collapse;"))
          (tr (td (@ (align . "center")
                     (style "padding:20px 12px 10px;"))
                  (p (@ (class . "pw-muted")
                        (style ,(mail-muted-style)))
                     ,(gettext
                       "this e-mail was powered by pingwing - the free and open Lisp-powered notification nexus"))
                  (p (@ (class . "pw-muted")
                        (style ,(mail-muted-style)))
                     (a (@ (href . "https://codeberg.org/jjba23/pingwing")
                           (style ,(mk-style `(("color" unquote
                                                (color-of mail-light
                                                          'muted))
                                               ("text-decoration" . "underline")))))
                        ,(gettext "🔗 pingwing's source code on Codeberg")))))))

(define* (mail-document #:key title content)
  "The whole HTML part of a message: TITLE in the head, CONTENT inside the
frosted panel, and the footer under it.  Every template hands its words here
and gets back a document that looks like the rest of them."
  `((html (@ (lang . "en"))
          ,(mail-head #:title title)
          (body (@ (class . "pw-body")
                   (style ,(mk-style `(("margin" . "0") ("padding" . "0")
                                       ("width" . "100%")
                                       ("background-color" unquote
                                        (color-of mail-light
                                                  'bg))
                                       ("background-image" unquote
                                        (color-of mail-light
                                                  'bg-gradient))
                                       ("font-family" unquote mail-sans-stack)
                                       ("font-size" . "16px")
                                       ("line-height" . "1.6")
                                       ("color" unquote
                                        (color-of mail-light
                                                  'ink))
                                       ("-webkit-font-smoothing" . "antialiased")))))
                (table (@ (role . "presentation")
                          (width . "100%")
                          (cellpadding . "0")
                          (cellspacing . "0")
                          (border . "0")
                          (style "border-collapse:collapse;"))
                       (tr (td (@ (align . "center")
                                  (style "padding:34px 16px;"))
                               (table (@ (role . "presentation")
                                         (width . "600")
                                         (cellpadding . "0")
                                         (cellspacing . "0")
                                         (border . "0")
                                         (style ,(mk-style `(("width" . "100%")
                                                             ("max-width" . "600px")
                                                             ("border-collapse" . "separate")
                                                             ("margin" . "0 auto")))))
                                      (tr (td ,(mail-panel content)))
                                      (tr (td ,mail-footer))))))))))
