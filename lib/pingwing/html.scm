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

(define-module (pingwing html)
  #:use-module (ice-9 textual-ports)
  #:use-module (ice-9 time)
  #:use-module (ice-9 format)
  #:use-module (ice-9 string-fun)
  #:use-module (ice-9 iconv))

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

(define-public mail-footer
  `((hr)
    (p (em ,(gettext
             "this e-mail was powered by pingwing - the free and open Lisp-powered notification nexus")))
    (a (@ (href . "https://codeberg.org/jjba23/pingwing"))
       ,(gettext "see pingwing's source code on Codeberg"))))
