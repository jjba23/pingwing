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

(define-module (pingwing css)
  #:use-module (ice-9 textual-ports)
  #:use-module (ice-9 time)
  #:use-module (ice-9 format)
  #:use-module (ice-9 string-fun)
  #:use-module (ice-9 iconv)
  #:export (mk-kv-conf-lines mk-css-conf-lines mk-style mail-style))

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

(define (mk-style xs)
  (string-join (map (lambda (x)
                      (format #f "~a: ~a;"
                              (car x)
                              (cdr x))) xs) " "))

(define mail-style
  (let* ((common-style (mk-css-conf-lines `((".button-link"
                                             (border-radius . "0.8em")
                                             (font-weight . bold)
                                             (padding . "0.8em"))
                                            (p (font-size . "1.2em")
                                               (margin-top . "1.0em"))
                                            (a (font-size . "1.2em")
                                               (margin-top . "1.0em"))
                                            (td (font-size . "1.2em"))
                                            (dl (padding . "1.2em")
                                                (font-size . "1.2em")
                                                (border-radius . "0.6em")
                                                (margin-top . "0.6em")
                                                (margin-bottom . "0.6em")))))
         (light-style (mk-css-conf-lines `(("h1, h2, h3, h4, p"
                                            (color . "#2b3339"))
                                           ("button" (background . "#a7c080")
                                            (color . "#2b3339")))))
         (dark-style (mk-css-conf-lines `(("h1, h2, h3, h4, p"
                                           (color . "#d3c6aa"))
                                          ("button" (background . "#a7c080")
                                           (color . "#2b3339")))))
         (style (string-replace-substring (string-join (list common-style
                                                        light-style
                                                        "@media (prefers-color-scheme: dark) {\n"
                                                        dark-style "}") "\n")
                                          "\n" "")))
    style))

