;;; pingwing -- the free and open Lisp-powered notification nexus

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; pingwing is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; pingwing is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with pingwing.  If not, see <https://www.gnu.org/licenses/>.

(define-module (pingwing css)
  #:use-module (ice-9 textual-ports)
  #:use-module (ice-9 time)
  #:use-module (ice-9 format)
  #:use-module (ice-9 string-fun)
  #:use-module (ice-9 iconv))

;; Create a CSS configuration from PAIRS, a selector to values alist.
(begin
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
                                                   #:template "  ~a: ~a;\n"))
                                         (display "}\n\n")) pairs))))
  (export mk-css-conf-lines))

(define-public (->style xs)
  (string-join (map (lambda (x)
                      (format #f "~a: ~a;"
                              (car x)
                              (cdr x))) xs) " "))

